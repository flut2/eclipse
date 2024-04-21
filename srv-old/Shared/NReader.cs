using System.IO;
using System.Text;

namespace Shared; 

public class NReader : BinaryReader
{
    public NReader(Stream s) : base(s, Encoding.UTF8)
    {
    }

    public string ReadNullTerminatedString()
    {
        var ret = new StringBuilder();
        var b = ReadByte();
        while (b != 0)
        {
            ret.Append((char)b);
            b = ReadByte();
        }

        return ret.ToString();
    }

    public string ReadUTF()
    {
        return Encoding.UTF8.GetString(ReadBytes(ReadInt16()));
    }

    public string Read32UTF()
    {
        return Encoding.UTF8.GetString(ReadBytes(ReadInt32()));
    }
}