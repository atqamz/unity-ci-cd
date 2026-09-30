using System;
using System.IO;
using System.Linq;
using UnityEditor.Build;

public static class WebGLBuildOutputValidator
{
    static readonly string[] RequiredPayloadFragments = { ".loader.js", ".framework.js", ".wasm" };

    public static void ValidateOrThrow(string playerRoot)
    {
        var problem = FindProblem(playerRoot);
        if (problem != null)
            throw new BuildFailedException($"WebGL player at '{playerRoot}' is not deployable: {problem}.");
    }

    public static string FindProblem(string playerRoot)
    {
        if (!Directory.Exists(playerRoot))
            return "the directory does not exist";

        var index = new FileInfo(Path.Combine(playerRoot, "index.html"));
        if (!index.Exists)
            return "index.html is missing";
        if (index.Length == 0)
            return "index.html is empty";

        var build = new DirectoryInfo(Path.Combine(playerRoot, "Build"));
        if (!build.Exists)
            return "Build/ is missing";

        var payload = build.GetFiles("*", SearchOption.AllDirectories)
            .Where(file => file.Length > 0)
            .Select(file => file.Name)
            .ToArray();
        var missing = RequiredPayloadFragments
            .Where(fragment => !payload.Any(name => name.IndexOf(fragment, StringComparison.OrdinalIgnoreCase) >= 0))
            .ToArray();
        return missing.Length == 0 ? null : $"Build/ has no non-empty *{string.Join("*, *", missing)}* file";
    }
}
