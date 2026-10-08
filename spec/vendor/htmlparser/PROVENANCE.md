# PROVENANCE

`htmlparser.lua` and `htmlparser/` are vendored from msva/lua-htmlparser at commit
`5ce9a775a345cf458c0388d7288e246bb1b82bff`, which is the exact commit koreader-base
pins in `thirdparty/lua-htmlparser/CMakeLists.txt`. LGPL-3.0; its license file is
kept beside this note.

This copy exists only so `busted` runs on a laptop. At runtime the plugin loads
KOReader's own bundled copy of the same library; nothing here ships to a device. Do
not modify these files; bump the pin only in lockstep with koreader-base.
