using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System.IO;

public class GenerateSceneBundle
{
    [MenuItem("Assets/Build Scene AssetBundle", false, 2000)]
    private static void BuildSelectedSceneBundle()
    {
        var scene = Selection.activeObject as SceneAsset;
        if (scene == null)
        {
            Debug.LogError("Selected asset is not a scene.");
            return;
        }
        string scenePath = AssetDatabase.GetAssetPath(scene);
        string sceneName = Path.GetFileNameWithoutExtension(scenePath);

        string outputPath = "Assets/SceneBundles";
        Directory.CreateDirectory(outputPath);

        BuildPipeline.BuildAssetBundles(outputPath,
        new AssetBundleBuild[]
        {
            new AssetBundleBuild
            {
                assetBundleName = sceneName.ToLower() + ".unity3d",
                assetNames = new string[] { scenePath }
            }
        },
        BuildAssetBundleOptions.None,
        EditorUserBuildSettings.activeBuildTarget);
    }

    [MenuItem("Assets/Build Scene AssetBundle", true)]
    private static bool ValidateBuildSelectedSceneBundle()
    {
        return Selection.activeObject is SceneAsset;
    }
}
