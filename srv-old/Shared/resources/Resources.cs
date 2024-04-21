using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using NLog;
using System.IO;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace Shared.resources; 

public class Resources
{
    public string ResourcePath { get; private set; }
    public AppSettings Settings { get; private set; }
    public XmlData GameData { get; private set; }
    public WorldData Worlds { get; private set; }
    public ChangePassword ChangePass { get; private set; }

    public IEnumerable<XElement> RawXmlBehaviors;

    public Resources(string resourcePath, bool wServer = false)
    {
        ResourcePath = resourcePath;
        Settings = new AppSettings(resourcePath + "/data/init.xml");
        GameData = new XmlData(resourcePath);

        if (!wServer)
        {
            ChangePass = new ChangePassword(resourcePath + "/data/changePassword");
        }
        else
        {
            LoadRawXmlBehaviors(resourcePath);
            Worlds = new WorldData(resourcePath + "/worlds", GameData);
        }
    }

    public void LoadRawXmlBehaviors(string path)
    {
        RawXmlBehaviors = SetRawXmlBehaviors(path + "/logic");
    }

    private IEnumerable<XElement> SetRawXmlBehaviors(string basePath)
    {
        var xmls = Directory.EnumerateFiles(basePath, "*.xml", SearchOption.AllDirectories).ToArray();
        for (var i = 0; i < xmls.Length; i++)
        {
            var xml = XElement.Parse(File.ReadAllText(xmls[i]));
            foreach (var elem in xml.Elements().Where(x => x.Name == "BehaviorEntry"))
                yield return elem;
        }
    }
}