# Load the System.Speech assembly from the GAC.
#
# System.Speech ships with the .NET Framework on every Windows install, so there is
# nothing to download. The original version of this file pointed -Path at
#   C:\Program Files (x86)\Reference Assemblies\...\v4.8.1\System.Speech.dll
# which is wrong for two reasons:
#   1. Reference Assemblies are compile-time metadata stubs, not runnable binaries.
#   2. That folder only exists if a .NET Framework developer/targeting pack is installed.
# The real assembly lives in C:\Windows\Microsoft.NET\assembly\GAC_MSIL\System.Speech\.
#
# NOTE: This module requires Windows PowerShell 5.1 (powershell.exe). System.Speech is
# not available on PowerShell 6+/Core. TTSMonitor.cmd already invokes powershell.exe.

Add-Type -AssemblyName System.Speech

# Derive the compile reference from the assembly the runtime actually loaded, so this
# keeps working across machines and future .NET Framework versions.
$assemblyPath = [AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.GetName().Name -eq 'System.Speech' } |
    Select-Object -First 1 -ExpandProperty Location

if (-not $assemblyPath) {
    throw "Could not locate the System.Speech assembly. Are you running this on powershell.exe (5.1) rather than pwsh?"
}

Add-Type -ReferencedAssemblies $assemblyPath -TypeDefinition @"

using System;
using System.Speech.Synthesis;
public class TTS {
    public static void SpeakText(string text, string voiceName = "Microsoft Zira Desktop", int rate = 1, int volume = 100) {
        using (var synth = new SpeechSynthesizer()) {

            // SelectVoice throws ArgumentException if the named voice is not installed.
            // Fall back to the system default rather than losing the whole message.
            bool voiceFound = false;
            if (!string.IsNullOrEmpty(voiceName)) {
                foreach (InstalledVoice v in synth.GetInstalledVoices()) {
                    if (v.Enabled && v.VoiceInfo.Name == voiceName) { voiceFound = true; break; }
                }
            }
            if (voiceFound) { synth.SelectVoice(voiceName); }

            // Clamp so out-of-range values coming from the queue JSON cannot throw.
            if (rate < -10) { rate = -10; } else if (rate > 10) { rate = 10; }
            if (volume < 0) { volume = 0; } else if (volume > 100) { volume = 100; }

            synth.Rate = rate;       // Rate:   -10 (slowest) to 10 (fastest)
            synth.Volume = volume;   // Volume: 0 to 100
            synth.Speak(text);
        }
    }

    // Handy for checking what is actually available on this machine.
    public static string[] ListVoices() {
        var synth = new SpeechSynthesizer();
        var voices = synth.GetInstalledVoices();
        var names = new System.Collections.Generic.List<string>();
        foreach (InstalledVoice v in voices) {
            if (v.Enabled) { names.Add(v.VoiceInfo.Name); }
        }
        synth.Dispose();
        return names.ToArray();
    }
}
"@
# USAGE: [TTS]::SpeakText("Testing different settings for text-to-speech.", "Microsoft Zira Desktop", 2, 90)
# USAGE: [TTS]::ListVoices()
