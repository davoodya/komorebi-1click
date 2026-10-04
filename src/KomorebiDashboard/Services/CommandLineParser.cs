using KomorebiDashboard.Models;

namespace KomorebiDashboard.Services;

/// <summary>
/// The CLI twin's parser. It resolves verbs through the SAME
/// <see cref="VerbRegistry"/> the GUI binds to, so the two cannot dispatch to
/// different scripts or report different help (ADR-0013).
/// </summary>
public sealed class CommandLineParser
{
    /// <summary>What the parser understood.</summary>
    /// <param name="Verb">The resolved definition, or null when unknown.</param>
    /// <param name="Arguments">Arguments to forward to the script.</param>
    /// <param name="WantsHelp">True for --help or for a verb with no arguments.</param>
    /// <param name="Error">A message to show, or null when the input was valid.</param>
    public sealed record Result(
        VerbDefinition? Verb,
        IReadOnlyList<string> Arguments,
        bool WantsHelp,
        string? Error);

    /// <summary>
    /// Parse an argument vector. The first token is the verb; everything after
    /// it is forwarded to the script untouched.
    /// </summary>
    public Result Parse(IReadOnlyList<string> args)
    {
        if (args.Count == 0 || args[0] is "-h" or "--help" or "help")
        {
            return new Result(null, Array.Empty<string>(), WantsHelp: true, Error: null);
        }

        var requested = args[0];
        var def = VerbRegistry.Find(requested);
        var rest = args.Skip(1).ToList();

        // ADR-0013 spells the per-script forms `ahk enable <name>` and
        // `ahk disable <name>`, while `ahk on|off` toggles all three. The
        // registry stores the per-script forms as their own rows (ahk-enable /
        // ahk-disable) so each is a real row with its own help and handler;
        // here the two-part spelling is folded onto that row.
        if (def is not null && def.Verb == "ahk" && rest.Count > 0)
        {
            var mapped = rest[0].ToLowerInvariant() switch
            {
                "enable"  => "ahk-enable",
                "disable" => "ahk-disable",
                _         => null,
            };

            if (mapped is not null && VerbRegistry.Find(mapped) is { } target)
            {
                def = target;
                rest = rest.Skip(1).ToList();
            }
        }

        if (def is null)
        {
            return new Result(
                null, Array.Empty<string>(), WantsHelp: false,
                Error: $"Unknown verb '{requested}'. Run with --help for the verb list.");
        }

        // A bare verb with no arguments is almost always someone asking what it
        // does, so show its help instead of running it.
        if (rest.Count == 0 && def.Arguments.Contains('<'))
        {
            return new Result(def, rest, WantsHelp: true, Error: null);
        }

        return new Result(def, rest, WantsHelp: false, Error: null);
    }
}