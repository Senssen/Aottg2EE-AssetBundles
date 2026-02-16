using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System.IO;

public class GenerateAssetBundle
{
    [MenuItem("Assets/Build AssetBundle", false, 2000)]
    private static void BuildSelectedSceneBundle()
    {
        var objects = Selection.objects;
        string[] paths = new string[objects.Length];
        for (int i = 0; i < objects.Length; i++)        {
            paths[i] = AssetDatabase.GetAssetPath(objects[i]);
        }

        string outputPath = "Assets/Bundles";
        Directory.CreateDirectory(outputPath);

        BuildPipeline.BuildAssetBundles(outputPath,
        new AssetBundleBuild[]
        {
            new AssetBundleBuild
            {
                assetBundleName = $"{objects[0].name.ToLower()}",
                assetNames = paths
            }
        },
        BuildAssetBundleOptions.None,
        EditorUserBuildSettings.activeBuildTarget);
    }
}
