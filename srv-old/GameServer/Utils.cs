using System.Collections;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using NLog;

namespace GameServer; 

internal static class PacketUtils {
    private static Logger Log = LogManager.GetCurrentClassLogger();
    public const int SEND_BUFFER_LEN = ushort.MaxValue;
    public const int RECV_BUFFER_LEN = ushort.MaxValue;

    public static byte ReadByte(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 1 > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        return Unsafe.ReadUnaligned<byte>(ref Unsafe.Add(ref spanRef, ptr++));
    }

    public static bool ReadBool(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 1 > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        return Unsafe.ReadUnaligned<bool>(ref Unsafe.Add(ref spanRef, ptr++));
    }

    public static char ReadChar(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 1 > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        return Unsafe.ReadUnaligned<char>(ref Unsafe.Add(ref spanRef, ptr++));
    }

    public static short ReadShort(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 2 > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        var i = Unsafe.ReadUnaligned<short>(ref Unsafe.Add(ref spanRef, ptr));
        ptr += 2;
        return i;
    }

    public static ushort ReadUShort(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 2 > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        var i = Unsafe.ReadUnaligned<ushort>(ref Unsafe.Add(ref spanRef, ptr));
        ptr += 2;
        return i;
    }

    public static int ReadInt(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 4 > len) {
            throw new Exception("Receive buffer attempted to read out of bounds");
        }

        var i = Unsafe.ReadUnaligned<int>(ref Unsafe.Add(ref spanRef, ptr));
        ptr += 4;
        return i;
    }

    public static uint ReadUInt(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 4 > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        var i = Unsafe.ReadUnaligned<uint>(ref Unsafe.Add(ref spanRef, ptr));
        ptr += 4;
        return i;
    }
    
    public static long ReadLong(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 8 > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        var i = Unsafe.ReadUnaligned<long>(ref Unsafe.Add(ref spanRef, ptr));
        ptr += 8;
        return i;
    }

    public static ulong ReadULong(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 8 > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        var i = Unsafe.ReadUnaligned<ulong>(ref Unsafe.Add(ref spanRef, ptr));
        ptr += 8;
        return i;
    }

    public static float ReadFloat(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 4 > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        var i = Unsafe.ReadUnaligned<float>(ref Unsafe.Add(ref spanRef, ptr));
        ptr += 4;
        return i;
    }

    public static string ReadString(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 2 > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        var strLen = Unsafe.ReadUnaligned<ushort>(ref Unsafe.Add(ref spanRef, ptr));
        ptr += 2;
        if (ptr + strLen > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        Span<byte> s = stackalloc byte[strLen];
        Unsafe.CopyBlockUnaligned(ref MemoryMarshal.GetReference(s), ref Unsafe.Add(ref spanRef, ptr), strLen);
        ptr += strLen;
        return Encoding.ASCII.GetString(s);
    }

    public static bool[] ReadBoolArray(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 2 > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        var arrLen = Unsafe.ReadUnaligned<short>(ref Unsafe.Add(ref spanRef, ptr));
        ptr += 2;
        if (ptr + arrLen > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        var ret = new bool[arrLen];
        for (var i = 0; i < arrLen; i++)
            ret[i] = Unsafe.ReadUnaligned<bool>(ref Unsafe.Add(ref spanRef, ptr++));

        return ret;
    }

    public static TimedPosition[] ReadTimedPosArray(ref int ptr, ref byte spanRef, int len) {
        if (ptr + 2 > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        var arrLen = Unsafe.ReadUnaligned<ushort>(ref Unsafe.Add(ref spanRef, ptr));
        ptr += 2;
        if (ptr + arrLen > len)
            throw new Exception("Receive buffer attempted to read out of bounds");

        var ret = new TimedPosition[arrLen];
        for (var i = 0; i < arrLen; i++)
            ret[i] = new TimedPosition {
                Time = ReadLong(ref ptr, ref spanRef, len),
                X = ReadFloat(ref ptr, ref spanRef, len),
                Y = ReadFloat(ref ptr, ref spanRef, len)
            };

        return ret;
    }

    public static void WriteByte(ref int ptr, ref byte spanRef, byte i) {
        if (ptr + 1 > SEND_BUFFER_LEN)
            throw new Exception("Send buffer attempted to write out of bounds");

        Unsafe.WriteUnaligned(ref Unsafe.Add(ref spanRef, ptr++), i);
    }

    public static void WriteSByte(ref int ptr, ref byte spanRef, sbyte i) {
        if (ptr + 1 > SEND_BUFFER_LEN)
            throw new Exception("Send buffer attempted to write out of bounds");

        Unsafe.WriteUnaligned(ref Unsafe.Add(ref spanRef, ptr++), i);
    }

    public static void WriteBool(ref int ptr, ref byte spanRef, bool b) {
        if (ptr + 1 > SEND_BUFFER_LEN)
            throw new Exception("Send buffer attempted to write out of bounds");

        Unsafe.WriteUnaligned(ref Unsafe.Add(ref spanRef, ptr++), b);
    }

    public static void WriteChar(ref int ptr, ref byte spanRef, char i) {
        if (ptr + 1 > SEND_BUFFER_LEN)
            throw new Exception("Send buffer attempted to write out of bounds");

        Unsafe.WriteUnaligned(ref Unsafe.Add(ref spanRef, ptr++), i);
    }

    public static void WriteShort(ref int ptr, ref byte spanRef, short i) {
        if (ptr + 2 > SEND_BUFFER_LEN)
            throw new Exception("Send buffer attempted to write out of bounds");

        Unsafe.WriteUnaligned(ref Unsafe.Add(ref spanRef, ptr), i);
        ptr += 2;
    }

    public static void WriteUShort(ref int ptr, ref byte spanRef, ushort i) {
        if (ptr + 2 > SEND_BUFFER_LEN)
            throw new Exception("Send buffer attempted to write out of bounds");

        Unsafe.WriteUnaligned(ref Unsafe.Add(ref spanRef, ptr), i);
        ptr += 2;
    }

    public static void WriteInt(ref int ptr, ref byte spanRef, int i) {
        if (ptr + 4 > SEND_BUFFER_LEN)
            throw new Exception("Send buffer attempted to write out of bounds");

        Unsafe.WriteUnaligned(ref Unsafe.Add(ref spanRef, ptr), i);
        ptr += 4;
    }

    public static void WriteUInt(ref int ptr, ref byte spanRef, uint i) {
        if (ptr + 4 > SEND_BUFFER_LEN)
            throw new Exception("Send buffer attempted to write out of bounds");

        Unsafe.WriteUnaligned(ref Unsafe.Add(ref spanRef, ptr), i);
        ptr += 4;
    }
    
    public static void WriteLong(ref int ptr, ref byte spanRef, long i) {
        if (ptr + 8 > SEND_BUFFER_LEN)
            throw new Exception("Send buffer attempted to write out of bounds");

        Unsafe.WriteUnaligned(ref Unsafe.Add(ref spanRef, ptr), i);
        ptr += 8;
    }

    public static void WriteULong(ref int ptr, ref byte spanRef, ulong i) {
        if (ptr + 8 > SEND_BUFFER_LEN)
            throw new Exception("Send buffer attempted to write out of bounds");

        Unsafe.WriteUnaligned(ref Unsafe.Add(ref spanRef, ptr), i);
        ptr += 8;
    }

    public static void WriteFloat(ref int ptr, ref byte spanRef, float i) {
        if (ptr + 4 > SEND_BUFFER_LEN)
            throw new Exception("Send buffer attempted to write out of bounds");

        Unsafe.WriteUnaligned(ref Unsafe.Add(ref spanRef, ptr), i);
        ptr += 4;
    }

    public static void WriteString(ref int ptr, ref byte spanRef, string s) {
        if (ptr + 2 + (ushort) s.Length > SEND_BUFFER_LEN)
            throw new Exception("Send buffer attempted to write out of bounds");

        WriteUShort(ref ptr, ref spanRef, (ushort) s.Length);
        foreach (var b in s)
            WriteChar(ref ptr, ref spanRef, b);
    }
}

internal static class MathsUtils {
    public static double Dist(double x1, double y1, double x2, double y2) {
        return Math.Sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2));
    }

    public static double DistSqr(double x1, double y1, double x2, double y2) {
        return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
    }

    public static double DistSqr(int x1, int y1, int x2, int y2) {
        return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
    }

    // http://stackoverflow.com/questions/1042902/most-elegant-way-to-generate-prime-numbers/1072205#1072205
    public static List<int> GeneratePrimes(int n) {
        var limit = ApproximateNthPrime(n);
        var bits = SieveOfEratosthenes(limit);
        var primes = new List<int>(n);
        for (int i = 0, found = 0; i < limit && found < n; i++)
            if (bits[i]) {
                primes.Add(i);
                found++;
            }

        return primes;
    }

    private static int ApproximateNthPrime(int nn) {
        var n = (double) nn;
        double p;
        if (nn >= 7022)
            p = n * Math.Log(n) + n * (Math.Log(Math.Log(n)) - 0.9385);
        else if (nn >= 6)
            p = n * Math.Log(n) + n * Math.Log(Math.Log(n));
        else if (nn > 0)
            p = new int[] {2, 3, 5, 7, 11}[nn - 1];
        else
            p = 0;

        return (int) p;
    }

    private static BitArray SieveOfEratosthenes(int limit) {
        var bits = new BitArray(limit + 1, true);
        bits[0] = false;
        bits[1] = false;
        for (var i = 0; i * i <= limit; i++)
            if (bits[i])
                for (var j = i * i; j <= limit; j += i)
                    bits[j] = false;

        return bits;
    }
}