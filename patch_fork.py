import sys
import os

path = '/Users/casazza/Repositories/schrodinger/schrodinger-agentic-stack/nix/module.nix'
if not os.path.exists(path):
    print(f"Error: {path} not found")
    sys.exit(1)

with open(path, 'r') as f:
    lines = f.readlines()

# Find the end of harnesses block
# Line 166 was '    harnesses = {'
# We look for the '    };' that closes it.
harnesses_end = -1
for i in range(165, len(lines)):
    if lines[i].strip() == '};' and lines[i].startswith('    '):
        harnesses_end = i
        break

if harnesses_end == -1:
    print("Error: Could not find end of harnesses block")
    sys.exit(1)

hermes_options = [
    "      hermes = {\n",
    "        enable = mkEnableOption ''\n",
    "          Wire Hermes Agent with agentic-stack skills. Symlinks `~/.hermes/skills` \n",
    "          to the merged skills directory.\n",
    "        '';\n",
    "        soulMd = mkOption {\n",
    "          type = types.nullOr types.lines;\n",
    "          default = null;\n",
    "          description = ''\n",
    "            Optional SOUL.md content for Hermes. If set, agentic-stack owns\n",
    "            `~/.hermes/SOUL.md`.\n",
    "          '';\n",
    "        };\n",
    "      };\n"
]

for j, line in enumerate(hermes_options):
    lines.insert(harnesses_end + j, line)

# Find the start of launchd/dream cycle block to insert config
dream_start = -1
for i in range(harnesses_end + len(hermes_options), len(lines)):
    if '# Nightly dream cycle' in lines[i]:
        dream_start = i
        break

if dream_start == -1:
    print("Error: Could not find start of dream cycle block")
    sys.exit(1)

hermes_config = [
    "    # Hermes adapter wiring.\n",
    "    home.file.\".hermes/skills\" = mkIf cfg.harnesses.hermes.enable {\n",
    "      source = cfg.skills.effectiveDir;\n",
    "    };\n",
    "\n",
    "    home.file.\".hermes/SOUL.md\" = mkIf (cfg.harnesses.hermes.enable && cfg.harnesses.hermes.soulMd != null) {\n",
    "      text = cfg.harnesses.hermes.soulMd;\n",
    "    };\n",
    "\n"
]

for j, line in enumerate(hermes_config):
    lines.insert(dream_start + j, line)

with open(path, 'w') as f:
    f.writelines(lines)
print("Successfully patched module.nix")
