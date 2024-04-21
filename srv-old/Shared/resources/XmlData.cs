using System.Xml.Linq;
using System.Xml.XPath;
using NLog;

namespace Shared.resources; 

public class XmlData {
    private static Logger log = LogManager.GetCurrentClassLogger();

    public List<MerchantList> MerchantLists;

    public Dictionary<ushort, XElement> ObjectTypeToElement;
    public Dictionary<ushort, string> ObjectTypeToId;
    public Dictionary<string, ushort> IdToObjectType;
    public Dictionary<string, ushort> DisplayIdToObjectType;
    public Dictionary<ushort, XElement> ItemTypeToElement;
    public Dictionary<ushort, string> ItemTypeToId;
    public Dictionary<string, ushort> IdToItemType;
    public Dictionary<string, ushort> DisplayIdToItemType;
    public Dictionary<ushort, XElement> TileTypeToElement;
    public Dictionary<ushort, string> TileTypeToId;
    public Dictionary<string, ushort> IdToTileType;
    public Dictionary<ushort, TileDesc> Tiles;
    public Dictionary<ushort, Item> Items;
    public Dictionary<ushort, ObjectDesc> ObjectDescs;
    public Dictionary<ushort, PortalDesc> Portals;
    public Dictionary<ushort, SkinDesc> Skins;
    public Dictionary<ushort, PlayerDesc> Classes;
    public Dictionary<ushort, ObjectDesc> Merchants;
    public Dictionary<int, ItemType> SlotType2ItemType;

    private string basePath;
        
    public XmlData(string path) {
        log.Info("Loading xml data...");

        MerchantLists = new List<MerchantList>();

        ObjectTypeToElement = new Dictionary<ushort, XElement>();
        ObjectTypeToId = new Dictionary<ushort, string>();
        IdToObjectType = new Dictionary<string, ushort>(StringComparer.InvariantCultureIgnoreCase);
        DisplayIdToObjectType = new Dictionary<string, ushort>(StringComparer.InvariantCultureIgnoreCase);
        ItemTypeToElement = new Dictionary<ushort, XElement>();
        ItemTypeToId = new Dictionary<ushort, string>();
        IdToItemType = new Dictionary<string, ushort>(StringComparer.InvariantCultureIgnoreCase);
        DisplayIdToItemType = new Dictionary<string, ushort>(StringComparer.InvariantCultureIgnoreCase);
        TileTypeToElement = new Dictionary<ushort, XElement>();
        TileTypeToId = new Dictionary<ushort, string>();
        IdToTileType = new Dictionary<string, ushort>(StringComparer.InvariantCultureIgnoreCase);
        Tiles = new Dictionary<ushort, TileDesc>();
        Items = new Dictionary<ushort, Item>();
        ObjectDescs = new Dictionary<ushort, ObjectDesc>();
        Portals = new Dictionary<ushort, PortalDesc>();
        Skins = new Dictionary<ushort, SkinDesc>();
        Classes = new Dictionary<ushort, PlayerDesc>();
        Merchants = new Dictionary<ushort, ObjectDesc>();
        SlotType2ItemType = new Dictionary<int, ItemType>();

        basePath = path;
        LoadXmls();
        LoadShops();

        log.Info("Finish loading game data.");
        log.Info("{0} Items", Items.Count);
        log.Info("{0} Tiles", Tiles.Count);
        log.Info("{0} Objects", ObjectDescs.Count);
        log.Info("{0} Skins", Skins.Count);
        log.Info("{0} Classes", Classes.Count);
        log.Info("{0} Portals", Portals.Count);
        log.Info("{0} Merchants", Merchants.Count);
    }

    public void LoadXmls() {
        var xmls = Directory.EnumerateFiles(basePath + "/xmls", "*.xml", SearchOption.AllDirectories).ToArray();
        for (var i = 0; i < xmls.Length; i++) {
            var xml = File.ReadAllText(xmls[i]);
            ProcessXml(XElement.Parse(xml));
        }
    }

    public void ClearDictionaries() {
        ObjectTypeToElement.Clear();
        ObjectTypeToId.Clear();
        IdToObjectType.Clear();
        DisplayIdToObjectType.Clear();
        ItemTypeToElement.Clear();
        ItemTypeToId.Clear();
        IdToItemType.Clear();
        DisplayIdToItemType.Clear();
        TileTypeToElement.Clear();
        TileTypeToId.Clear();
        IdToTileType.Clear();
        Tiles.Clear();
        Items.Clear();
        ObjectDescs.Clear();
        Classes.Clear();
        Portals.Clear();
        Skins.Clear();
        Merchants.Clear();
        SlotType2ItemType.Clear();
    }
    
    private void AddItems(XElement root) {
        foreach (var elem in root.XPathSelectElements("//Item")) {
            var id = elem.Attribute("id")!.Value;

            var typeAttr = elem.Attribute("type");
            if (typeAttr == null) {
                log.Error($"{id} is missing type number. Skipped.");
                continue;
            }

            var type = (ushort) Utils.FromString(typeAttr.Value);

            if (ItemTypeToId.TryGetValue(type, out var value1))
                log.Warn("'{0}' and '{1}' has the same ID of 0x{2:x4}!", id, value1, type);
            else {
                ItemTypeToId[type] = id;
                ItemTypeToElement[type] = elem;
            }

            if (IdToItemType.TryGetValue(id, out var value))
                log.Warn("0x{0:x4} and 0x{1:x4} has the same name of {2}!", type, value, id);
            else
                IdToItemType[id] = type;

            var displayId = elem.Element("DisplayId") != null ? elem.Element("DisplayId")!.Value : null;
            var displayName = displayId == null ? id : displayId[0].Equals('{') ? id : displayId;

            DisplayIdToItemType[displayName] = type;
            Items[type] = new Item(type, elem);
        }
    }

    private void AddObjects(XElement root) {
        foreach (var elem in root.XPathSelectElements("//Object")) {
            if (elem.Element("Class") == null)
                continue;

            var cls = elem.Element("Class")!.Value;
            var id = elem.Attribute("id")!.Value;

            var typeAttr = elem.Attribute("type");
            if (typeAttr == null) {
                log.Error($"{id} is missing type number. Skipped.");
                continue;
            }

            var type = (ushort) Utils.FromString(typeAttr.Value);

            if (ObjectTypeToId.TryGetValue(type, out var value1))
                log.Warn("'{0}' and '{1}' has the same ID of 0x{2:x4}!", id, value1, type);
            else {
                ObjectTypeToId[type] = id;
                ObjectTypeToElement[type] = elem;
            }

            if (IdToObjectType.TryGetValue(id, out var value))
                log.Warn("0x{0:x4} and 0x{1:x4} has the same name of {2}!", type, value, id);
            else
                IdToObjectType[id] = type;

            var displayId = elem.Element("DisplayId") != null ? elem.Element("DisplayId")!.Value : null;
            var displayName = displayId == null ? id : displayId[0].Equals('{') ? id : displayId;

            DisplayIdToObjectType[displayName] = type;

            switch (cls) {
                case "Skin":
                    var skinDesc = SkinDesc.FromElem(type, elem);
                    if (skinDesc != null)
                        Skins[type] = skinDesc;
                    // might want to add skin description to objDesc
                    // dictionary so that skins can be merched...
                    // perhaps later
                    break;
                case "Player":
                    var pDesc = new PlayerDesc(type, elem);
                    SlotType2ItemType[pDesc.SlotTypes[0]] = ItemType.Weapon;
                    SlotType2ItemType[pDesc.SlotTypes[1]] = ItemType.Ability;
                    SlotType2ItemType[pDesc.SlotTypes[2]] = ItemType.Armor;
                    SlotType2ItemType[pDesc.SlotTypes[3]] = ItemType.Ring;
                    Classes[type] = new PlayerDesc(type, elem);
                    ObjectDescs[type] = Classes[type];
                    break;
                case "Portal":
                    Portals[type] = new PortalDesc(type, elem);
                    ObjectDescs[type] = Portals[type];
                    break;
                case "GuildMerchant":
                case "Merchant":
                case "PetMerchant":
                    Merchants[type] = new ObjectDesc(type, elem);
                    break;
                default:
                    ObjectDescs[type] = new ObjectDesc(type, elem);
                    break;
            }
        }
    }

    private void AddGrounds(XElement root) {
        foreach (var elem in root.XPathSelectElements("//Ground")) {
            var id = elem.Attribute("id")!.Value;

            var typeAttr = elem.Attribute("type");
            var type = (ushort) Utils.FromString(typeAttr?.Value);

            if (TileTypeToId.TryGetValue(type, out var value))
                log.Warn("'{0}' and '{1}' has the same ID of 0x{2:x4}!", id, value, type);
            if (IdToTileType.TryGetValue(id, out var value1))
                log.Warn("0x{0:x4} and 0x{1:x4} has the same name of {2}!", type, value1, id);

            TileTypeToId[type] = id;
            IdToTileType[id] = type;
            TileTypeToElement[type] = elem;

            Tiles[type] = new TileDesc(type, elem);
        }
    }

    private void ProcessXml(XElement root) {
        AddItems(root);
        AddObjects(root);
        AddGrounds(root);
    }

    public void LoadShops() {
        foreach (var e in XElement.Parse(File.ReadAllText(basePath + "/data/Merchants.xml")).XPathSelectElements("//List")) {
            MerchantLists.Add(new MerchantList(e, this));
        }
    }
}