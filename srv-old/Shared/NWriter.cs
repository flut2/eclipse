using System.IO;
using System.Text;

namespace Shared; 

public class NWriter : BinaryWriter
{
    public NWriter(Stream s) : base(s, Encoding.UTF8)
    {
    }

    public void WriteNullTerminatedString(string str)
    {
        Write(Encoding.UTF8.GetBytes(str));
        Write((byte)0);
    }

    public void WriteUTF(string str)
    {
        if (str == null)
            Write((short)0);
        else
        {
            var bytes = Encoding.UTF8.GetBytes(str);
            Write((short)bytes.Length);
            Write(bytes);
        }
    }

    public void Write32UTF(string str)
    {
        var bytes = Encoding.UTF8.GetBytes(str);
        Write(bytes.Length);
        Write(bytes);
    }
}