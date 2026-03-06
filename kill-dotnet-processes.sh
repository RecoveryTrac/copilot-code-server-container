#!/bin/bash
# Kill all .NET development processes that consume memory
# Safe to run - only targets build/language server processes, not your actual apps

echo "🧹 Killing .NET development processes..."

# Kill MSBuild worker processes
pkill -f "MSBuild.dll" && echo "✓ Killed MSBuild processes" || echo "  No MSBuild processes found"

# Kill Roslyn compiler server
pkill -f "VBCSCompiler" && echo "✓ Killed VBCSCompiler" || echo "  No VBCSCompiler found"

# Kill Roslyn Language Server
pkill -f "Microsoft.CodeAnalysis.LanguageServer" && echo "✓ Killed Roslyn Language Server" || echo "  No Roslyn Language Server found"

# Kill C# DevKit service hosts
pkill -f "Microsoft.VisualStudio.Code.ServiceHost" && echo "✓ Killed VS Code Service Hosts" || echo "  No Service Hosts found"

# Kill C# DevKit controllers
pkill -f "Microsoft.VisualStudio.Code.ServiceController" && echo "✓ Killed VS Service Controllers" || echo "  No Service Controllers found"

# Kill VS Code server (C# extension specific)
pkill -f "visualstudio-server.linux-x64" && echo "✓ Killed VS Server processes" || echo "  No VS Server processes found"

echo ""
echo "✅ Cleanup complete!"
echo "💾 Memory should be freed within a few seconds"
