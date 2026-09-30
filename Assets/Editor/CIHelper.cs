using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;

public static class CIHelper
{
    public static void Build()
    {
        try
        {
            BuildOrThrow(ReadArg("-buildOutput"));
        }
        catch (Exception exception)
        {
            Debug.LogError($"[CIHelper] Build failed: {exception}");
            EditorApplication.Exit(1);
        }
    }

    static void BuildOrThrow(string outputDirectory)
    {
        if (string.IsNullOrEmpty(outputDirectory))
            throw new ArgumentException("Pass -buildOutput <directory>.");

        var target = EditorUserBuildSettings.activeBuildTarget;
        var requested = ReadArg("-buildTarget");
        if (requested != null && (!Enum.TryParse(requested, true, out BuildTarget expected) || expected != target))
            throw new BuildFailedException($"-buildTarget {requested} was requested but {target} is active. Pass a BuildTarget name and install its platform module.");

        var scenes = EditorBuildSettings.scenes.Where(scene => scene.enabled).Select(scene => scene.path).ToArray();
        if (scenes.Length == 0)
            throw new BuildFailedException("No enabled scene in Build Settings.");

        var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
        {
            scenes = scenes,
            target = target,
            locationPathName = PlayerPath(outputDirectory, target),
        });
        if (report.summary.result != BuildResult.Succeeded)
            throw new BuildFailedException($"{target} build ended {report.summary.result} with {report.summary.totalErrors} error(s).");

        if (target == BuildTarget.WebGL)
            WebGLBuildOutputValidator.ValidateOrThrow(outputDirectory);

        Debug.Log($"[CIHelper] Built {target} into {outputDirectory} ({report.summary.totalSize} bytes).");
    }

    static string PlayerPath(string directory, BuildTarget target)
    {
        var name = PlayerSettings.productName;
        switch (target)
        {
            case BuildTarget.StandaloneLinux64: return Path.Combine(directory, name + ".x86_64");
            case BuildTarget.StandaloneWindows64: return Path.Combine(directory, name + ".exe");
            case BuildTarget.StandaloneOSX: return Path.Combine(directory, name + ".app");
            case BuildTarget.Android: return Path.Combine(directory, name + ".apk");
            default: return directory;
        }
    }

    static string ReadArg(string flag)
    {
        var args = Environment.GetCommandLineArgs();
        var index = Array.IndexOf(args, flag);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }
}
