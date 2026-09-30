using System.IO;
using NUnit.Framework;

public class WebGLBuildOutputValidatorTests
{
    [TestCase("", true)]
    [TestCase("index.html", false)]
    [TestCase("Build/Player.loader.js", false)]
    [TestCase("Build/Player.framework.js", false)]
    [TestCase("Build/Player.wasm", false)]
    public void AcceptsOnlyACompletePlayer(string removed, bool deployable)
    {
        var root = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        Directory.CreateDirectory(Path.Combine(root, "Build"));
        foreach (var file in new[] { "index.html", "Build/Player.loader.js", "Build/Player.framework.js", "Build/Player.wasm" })
            File.WriteAllText(Path.Combine(root, file), "payload");
        if (removed != "")
            File.Delete(Path.Combine(root, removed));

        try
        {
            Assert.That(WebGLBuildOutputValidator.FindProblem(root), deployable ? Is.Null : Is.Not.Null);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }
}
