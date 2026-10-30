"""List ELM history fields defined by hist_addfld calls at a git ref of an E3SM checkout.

Usage: python3 list_hist_fields.py <E3SM_ROOT> <git-ref> > fields.tsv
  e.g. python3 list_hist_fields.py ../E3SM origin/ez/fsca | grep -i sno

Output columns (tab-separated): name, units, default (active/inactive),
dimension (1d or 2d:<level>), long_name, source file.
"inactive" fields are only written if listed in hist_fincl*.
"""
import re
import subprocess
import sys

repo, ref = sys.argv[1], sys.argv[2]
ls = subprocess.run(["git", "-C", repo, "ls-tree", "-r", "--name-only", ref, "components/elm/src"],
                    capture_output=True, text=True)
if ls.returncode != 0:
    sys.exit(f"git ls-tree failed for repo '{repo}', ref '{ref}':\n{ls.stderr.strip()}")
files = ls.stdout.split()
out = {}
for f in files:
    if not f.endswith(".F90"):
        continue
    src = subprocess.run(["git", "-C", repo, "show", f"{ref}:{f}"],
                         capture_output=True, text=True, errors="replace").stdout
    # drop comments and join Fortran continuation lines
    src = re.sub(r"!.*", "", src)
    src = re.sub(r"&\s*\n\s*&?", " ", src)
    for m in re.finditer(r"call\s+hist_addfld(1d|2d)\s*\((.*?)\)\s*\n", src, re.I | re.S):
        args = m.group(2)

        def arg(key):
            found = re.search(rf"\b{key}\s*=\s*['\"]([^'\"]*)['\"]", args, re.I)
            return found[1] if found else ""

        name = arg("fname")
        if not name:
            continue
        default = "inactive" if arg("default").lower() == "inactive" else "active"
        dim = m.group(1) + (f":{arg('type2d')}" if arg("type2d") else "")
        out[name] = (arg("units"), default, dim, arg("long_name"), f.split("/")[-1])

for name in sorted(out):
    print("\t".join((name,) + out[name]))
