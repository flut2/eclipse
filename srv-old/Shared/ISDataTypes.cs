using System.ComponentModel;

namespace Shared; 

public enum Channel
{
    [Description("Network")] Network,
    [Description("Control")] Control,
    [Description("Chat")] Chat,
    [Description("RebootBehaviors")] RebootBehaviors
}

public enum ChatType
{
    Tell,
    Guild,
    Announce,
    GuildAnnounce,
    Invite,
    Info
}

public enum NetworkCode
{
    Join,
    Ping,
    Quit,
    Timeout
}

public enum ControlType
{
    Reboot
}

public struct NetworkMsg
{
    public NetworkCode Code;
    public ServerInfo Info;
}

public struct ChatMsg
{
    public ChatType Type;
    public string Inst;
    public int ObjId;
    public int Stars;
    public int Admin;
    public bool Hidden;
    public int From;
    public int To;
    public string Text;
    public string SrcIP;
}

public struct ControlMsg
{
    public ControlType Type;
    public string TargetInst;
    public string Issuer;
    public string Payload;
    public int Delay;
}
    
public struct RebootBehaviorMsg {
    public byte _;
}