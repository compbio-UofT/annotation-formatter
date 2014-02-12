package org.broad.tabix;

/* The MIT License

 Copyright (c) 2010 Broad Institute.
 Portions Copyright (c) 2011 University of Toronto.

 Permission is hereby granted, free of charge, to any person obtaining
 a copy of this software and associated documentation files (the
 "Software"), to deal in the Software without restriction, including
 without limitation the rights to use, copy, modify, merge, publish,
 distribute, sublicense, and/or sell copies of the Software, and to
 permit persons to whom the Software is furnished to do so, subject to
 the following conditions:

 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import net.sf.samtools.util.BlockCompressedInputStream;
import net.sf.samtools.util.BlockCompressedOutputStream;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

/**
 * Tabix writer, based on Heng Li's C implementation.
 * 
 * @author tarkvara
 */
public class TabixWriter extends TabixReader
{

    private static final Log LOG = LogFactory.getLog(TabixWriter.class);

    private static final Charset LATIN1 = Charset.forName("ISO-8859-1");

    public static final int TI_PRESET_GENERIC = 0;

    public static final int TI_PRESET_SAM = 1;

    public static final int TI_PRESET_VCF = 2;

    public static final int TI_FLAG_UCSC = 0x10000;

    public static final Conf GFF_CONF = new Conf(0, 1, 4, 5, '#', 0);

    public static final Conf BED_CONF = new Conf(TI_FLAG_UCSC, 1, 2, 3, '#', 0);

    public static final Conf PSLTBL_CONF = new Conf(TI_FLAG_UCSC, 15, 17, 18, '#', 0);

    public static final Conf SAM_CONF = new Conf(TI_PRESET_SAM, 3, 4, 0, '@', 0);

    public static final Conf VCF_CONF = new Conf(TI_PRESET_VCF, 1, 2, 0, '#', 0);

    /** The binning index. */
    List<Map<Integer, List<TPair64>>> binningIndex = new ArrayList<Map<Integer, List<TPair64>>>();

    /** The linear index. */
    List<List<Long>> linearIndex = new ArrayList<List<Long>>();

    public TabixWriter(File fn, Conf conf) throws Exception
    {
        super(fn.getAbsolutePath());
        applyConf(conf);
        this.mChr2tid = new LinkedHashMap<String, Integer>();
    }

    private void applyConf(Conf conf)
    {
        this.mPreset = conf.preset;
        this.mSc = conf.chrColumn;
        this.mBc = conf.startColumn;
        this.mEc = conf.endColumn;
        this.mMeta = conf.commentChar;
        this.mSkip = conf.linesToSkip;
    }

    public void createIndex(File fn) throws Exception
    {
        BlockCompressedInputStream fp = new BlockCompressedInputStream(fn);
        makeIndex(fp);
        fp.close();
        File indexFile = new File(fn + ".tbi");
        BlockCompressedOutputStream fpidx = new BlockCompressedOutputStream(indexFile);
        saveIndex(fpidx);
        fpidx.close();
    }

    private void makeIndex(BlockCompressedInputStream fp) throws Exception
    {
        int last_bin, save_bin;
        int last_coor, last_tid, save_tid;
        long save_off, last_off, lineno = 0, offset0 = -1;
        String str;

        save_bin = save_tid = last_tid = last_bin = 0xffffffff; // Was unsigned in C implementation.
        save_off = last_off = 0;
        last_coor = 0xffffffff; // Should be unsigned.
        while ((str = readLine(fp)) != null) {
            ++lineno;
            if (lineno <= this.mSkip || str.charAt(0) == this.mMeta) {
                last_off = fp.getFilePointer();
                continue;
            }
            TIntv intv = getIntv(str);
            if (intv.beg < 0 || intv.end < 0) {
                throw new Exception("The indexes overlap or are out of bounds.");
            }
            if (last_tid != intv.tid) { // change of chromosomes
                if (last_tid > intv.tid) {
                    throw new Exception(String.format(
                        "The chromosome blocks are not continuous at line %d, is the file sorted? [pos %d].", lineno,
                        intv.beg + 1));
                }
                last_tid = intv.tid;
                last_bin = 0xffffffff;
            } else if (last_coor > intv.beg) {
                throw new Exception(String.format("File out of order at line %d.", lineno));
            }
            long tmp = insertLinear(this.linearIndex.get(intv.tid), intv.beg, intv.end, last_off);
            if (last_off == 0) {
                offset0 = tmp;
            }
            if (intv.bin != last_bin) { // then possibly write the binning index
                if (save_bin != 0xffffffff) { // save_bin==0xffffffffu only happens to the first record
                    insertBinning(this.binningIndex.get(save_tid), save_bin, save_off, last_off);
                }
                save_off = last_off;
                save_bin = last_bin = intv.bin;
                save_tid = intv.tid;
                if (save_tid < 0) {
                    break;
                }
            }
            if (fp.getFilePointer() <= last_off) {
                throw new Exception(String.format("Bug in BGZF: %x < %x.", fp.getFilePointer(), last_off));
            }
            last_off = fp.getFilePointer();
            last_coor = intv.beg;
        }
        if (save_tid >= 0) {
            insertBinning(this.binningIndex.get(save_tid), save_bin, save_off, fp.getFilePointer());
        }
        mergeChunks();
        fillMissing();
        if (offset0 != -1 && !this.linearIndex.isEmpty() && this.linearIndex.get(0) != null) {
            int beg = (int) (offset0 >> 32), end = (int) (offset0 & 0xffffffff);
            for (int i = beg; i <= end; ++i) {
                this.linearIndex.get(0).set(i, 0L);
            }
        }
    }

    private void insertBinning(Map<Integer, List<TPair64>> binningForChr, int bin, long beg, long end)
    {
        if (!binningForChr.containsKey(bin)) {
            binningForChr.put(bin, new ArrayList<TPair64>());
        }
        List<TPair64> list = binningForChr.get(bin);
        list.add(new TPair64(beg, end));
    }

    private long insertLinear(List<Long> linearForChr, int beg, int end, long offset)
    {
        beg = beg >> TAD_LIDX_SHIFT;
        end = (end - 1) >> TAD_LIDX_SHIFT;

        // Expand the array if necessary.
        int newSize = Math.max(beg, end) + 1;
        while (linearForChr.size() < newSize) {
            linearForChr.add(0L);
        }
        if (beg == end) {
            if (linearForChr.get(beg) == 0L) {
                linearForChr.set(beg, offset);
            }
        } else {
            for (int i = beg; i <= end; ++i) {
                if (linearForChr.get(i) == 0L) {
                    linearForChr.set(i, offset);
                }
            }
        }
        return (long) beg << 32 | end;
    }

    private void mergeChunks()
    {
        for (int i = 0; i < this.binningIndex.size(); i++) {
            Map<Integer, List<TPair64>> binningForChr = this.binningIndex.get(i);
            for (Integer k : binningForChr.keySet()) {
                List<TPair64> p = binningForChr.get(k);
                int m = 0;
                for (int l = 1; l < p.size(); l++) {
                    if (p.get(m).v >> 16 == p.get(l).u >> 16) {
                        p.get(m).v = p.get(l).v;
                    } else {
                        p.set(++m, p.get(l));
                    }
                }
                while (p.size() > m + 1) {
                    p.remove(p.size() - 1);
                }
            }
        }
    }

    private void fillMissing()
    {
        for (int i = 0; i < this.linearIndex.size(); ++i) {
            List<Long> linearForChr = this.linearIndex.get(i);
            for (int j = 1; j < linearForChr.size(); ++j) {
                if (linearForChr.get(j) == 0) {
                    linearForChr.set(j, linearForChr.get(j - 1));
                }
            }
        }
    }

    public static void writeInt(final OutputStream os, int value) throws IOException
    {
        byte[] buf = new byte[4];
        ByteBuffer.wrap(buf).order(ByteOrder.LITTLE_ENDIAN).putInt(value);
        os.write(buf);
    }

    public static void writeLong(final OutputStream os, long value) throws IOException
    {
        byte[] buf = new byte[8];
        ByteBuffer.wrap(buf).order(ByteOrder.LITTLE_ENDIAN).putLong(value);
        os.write(buf);
    }

    private void saveIndex(BlockCompressedOutputStream fp) throws IOException
    {
        fp.write("TBI\1".getBytes(LATIN1));
        writeInt(fp, this.binningIndex.size());

        // Write the ti_conf_t
        writeInt(fp, this.mPreset);
        writeInt(fp, this.mSc);
        writeInt(fp, this.mBc);
        writeInt(fp, this.mEc);
        writeInt(fp, this.mMeta);
        writeInt(fp, this.mSkip);

        // Write sequence dictionary. Since mChr2tid is a LinkedHashmap, the keyset
        // will be returned in insertion order.
        int l = 0;
        for (String k : this.mChr2tid.keySet()) {
            l += k.length() + 1;
        }
        writeInt(fp, l);
        for (String k : this.mChr2tid.keySet()) {
            fp.write(k.getBytes(LATIN1));
            fp.write(0);
        }

        for (int i = 0; i < this.mChr2tid.size(); i++) {
            Map<Integer, List<TPair64>> binningForChr = this.binningIndex.get(i);

            // Write the binning index.
            writeInt(fp, binningForChr.size());
            for (int k : binningForChr.keySet()) {
                List<TPair64> p = binningForChr.get(k);
                writeInt(fp, k);
                writeInt(fp, p.size());
                for (TPair64 bin : p) {
                    writeLong(fp, bin.u);
                    writeLong(fp, bin.v);
                }
            }
            // Write the linear index.
            List<Long> linearForChr = this.linearIndex.get(i);
            writeInt(fp, linearForChr.size());
            for (int x = 0; x < linearForChr.size(); x++) {
                writeLong(fp, linearForChr.get(x));
            }
        }
    }

    /**
     * Override chr2tid so that getInv() adds new chromosomes as we read the source file.
     */
    @Override
    protected int chr2tid(String chr)
    {
        if (!this.mChr2tid.containsKey(chr)) {
            // Doesn't exist yet.
            this.mChr2tid.put(chr, this.mChr2tid.size());

            // Expand our indices.
            this.binningIndex.add(new HashMap<Integer, List<TPair64>>());
            this.linearIndex.add(new ArrayList<Long>());
        }
        return this.mChr2tid.get(chr);
    }

    /**
     * Override getIntv because it's a good time to figure out which bin things should go into.
     * 
     * @param line a line read from the source file
     * @return an object describing the interval
     */
    @Override
    protected TIntv getIntv(String line)
    {
        TIntv result = super.getIntv(line);
        result.bin = reg2bin(result.beg, result.end);
        return result;
    }

    //convert a region to a bin.
    //From the SAMv1.pdf manual:
    //Each bin spans 2^29, 2^26, 2^23, 2^20, 2^17, or 2^14 bp.  
    //bin 0 spans 512Mbp, bins 1–8 span 64Mbp, 9–72 8Mbp, 73–584 1Mbp, 585–4680 128Kbp 
    // and bins 4681–37449 span 16Kbp regions.
    private int reg2bin(int beg, int end)
    {
        --end;
        if (beg >> 14 == end >> 14) { //beg
            return 4681 + (beg >> 14);
        }
        if (beg >> 17 == end >> 17) {
            return 585 + (beg >> 17);
        }
        if (beg >> 20 == end >> 20) {
            return 73 + (beg >> 20); //
        }
        if (beg >> 23 == end >> 23) {
            return 9 + (beg >> 23); //max val: 2^9-1 + 9 = 520
        }
        if (beg >> 26 == end >> 26) {
            return 1 + (beg >> 26); //max val: 32
        }
        return 0;
    }

    public static class Conf
    {
        public final int preset;

        public final int chrColumn;

        public final int startColumn;

        public final int endColumn;

        public final char commentChar;

        public final int linesToSkip;

        public Conf(int preset, int chrColumn, int startColumn, int endColumn, char commentChar, int linesToSkip)
        {
            this.preset = preset;
            this.chrColumn = chrColumn;
            this.startColumn = startColumn;
            this.endColumn = endColumn;
            this.commentChar = commentChar;
            this.linesToSkip = linesToSkip;
        }
    }
}
