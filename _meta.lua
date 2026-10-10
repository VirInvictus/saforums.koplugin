-- name and version are plain strings on purpose: the on-device plugin
-- marketplaces regex-extract them from this file for install detection and
-- update comparison (spec: Platform and dependencies). They must match the
-- VERSION file and the release tag.
local _ = require("gettext")

return {
    name = "saforums",
    version = "0.5.0",
    fullname = _("SA Forums"),
    description = _([[Read the Something Awful Forums on your e-reader. Lurker-first: forum index, thread lists with unread counts, and thread pages rendered as post cards.]]),
}
