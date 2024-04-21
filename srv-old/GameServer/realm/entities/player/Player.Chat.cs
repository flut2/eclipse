namespace GameServer.realm.entities.player; 

partial class Player
{
    public void SendInfo(string text)
    {
        _client.SendText("", 0, 0, "", text, 0, 0xFFD700);
    }
    
    public void SendError(string text)
    {
        _client.SendText("", 0, 0, "", text, 0, 0xFF0000);
    }

    internal void TellReceived(int objId, int stars, int admin, string from, string to, string text)
    {
        Client.SendText(from, objId, 10, to, text, 0x00E6FF, 0x00E6FF);
    }
        
    internal void AnnouncementReceived(string text)
    {
        _client.Player.SendInfo("<Announcement> " + text);
    }

    internal void GuildReceived(int objId, int stars, int admin, string from, string text)
    {
        Client.SendText(from, 0, 10, "", text, 0x97C688, 0x97C688);
    }
}