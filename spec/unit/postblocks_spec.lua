require("spec.stubs")

local postblocks = require("saforums.postblocks")

-- every para block opens with TextBoxWidget's PTF header marker
local function text_of(block)
    return block.text:sub(#postblocks.PTF_HEADER + 1)
end

describe("postblocks", function()
    it("splits br-separated lines into paragraph blocks with bold markers", function()
        local blocks = postblocks.parse("plain line<br/><b>bold line</b><br/>tail")
        assert.equals(3, #blocks)
        assert.equals("para", blocks[1].type)
        assert.equals("plain line", text_of(blocks[1]))
        assert.equals(
            postblocks.BOLD_START .. "bold line" .. postblocks.BOLD_END,
            text_of(blocks[2]))
        assert.equals("tail", text_of(blocks[3]))
        -- every block opens with the PTF header TextBoxWidget expects
        for _, block in ipairs(blocks) do
            assert.matches("^" .. postblocks.PTF_HEADER, block.text)
        end
    end)

    it("decodes entities and collapses source whitespace", function()
        local blocks = postblocks.parse("caf&amp;eacute   with\n\n    gaps   and&nbsp;nbsp")
        assert.equals(1, #blocks)
        assert.equals("caf&eacute with gaps and nbsp", text_of(blocks[1]))
    end)

    it("extracts quotes with their headers, nesting flattens", function()
        local html = "<blockquote><h4>kirbysuperstar posted:</h4>" ..
            "outer words<blockquote><h4>inner posted:</h4>inner words</blockquote></blockquote>"
        local blocks = postblocks.parse(html)
        assert.equals("quote", blocks[1].type)
        assert.equals("kirbysuperstar posted:", blocks[1].header)
        -- the nested quote's markers flatten into the outer text
        assert.matches("inner posted:", blocks[1].text)
        assert.matches("inner words", blocks[1].text)
    end)

    it("keeps bold inside quotes", function()
        local html = "<blockquote><h4>x posted:</h4>see <b>this</b> now</blockquote>"
        local blocks = postblocks.parse(html)
        assert.matches(postblocks.BOLD_START .. "this" .. postblocks.BOLD_END, blocks[1].text)
    end)

    it("turns image placeholders into image blocks, carrying the source URL", function()
        local blocks = postblocks.parse(
            'hello<span class="imgref" src="https://img.fixture.invalid/pic.png">[image: pic.png]</span>bye')
        assert.equals(3, #blocks)
        assert.equals("image", blocks[2].type)
        assert.equals("[image: pic.png]", blocks[2].label)
        assert.equals("https://img.fixture.invalid/pic.png", blocks[2].src)
    end)

    it("turns embed placeholders into embed blocks", function()
        local blocks = postblocks.parse(
            'word<span class="embedref">[tweet: @someone]</span>')
        assert.equals(2, #blocks)
        assert.equals("embed", blocks[2].type)
        assert.equals("[tweet: @someone]", blocks[2].label)
    end)

    it("returns no blocks for an empty body", function()
        assert.equals(0, #postblocks.parse(""))
        assert.equals(0, #postblocks.parse(nil))
    end)

    it("extracts spoiler spans into spoiler blocks without the markers", function()
        local blocks = postblocks.parse('before<span class="spoiler">[spoiler] shh [/spoiler]</span>after')
        assert.equals(3, #blocks)
        assert.equals("spoiler", blocks[2].type)
        assert.equals("shh", blocks[2].text)
        assert.equals("before", text_of(blocks[1]))
        assert.equals("after", text_of(blocks[3]))
    end)

    it("keeps spoiler text without markers when the wrappers are missing", function()
        local blocks = postblocks.parse('<span class="spoiler">barely marked</span>')
        assert.equals(1, #blocks)
        assert.equals("spoiler", blocks[1].type)
        assert.equals("barely marked", blocks[1].text)
    end)
end)

describe("postblocks mentions", function()
    it("bold-marks bare occurrences of the username", function()
        local blocks = postblocks.parse("hey Brandon look at this", { username = "Brandon" })
        assert.equals(1, #blocks)
        assert.equals("hey " .. postblocks.BOLD_START .. "Brandon" .. postblocks.BOLD_END
            .. " look at this", text_of(blocks[1]))
    end)

    it("matches case-insensitively but not inside words", function()
        local blocks = postblocks.parse("Brandonaise, then BRANDON appears", { username = "Brandon" })
        assert.equals(1, #blocks)
        assert.equals("Brandonaise, then "
            .. postblocks.BOLD_START .. "BRANDON" .. postblocks.BOLD_END .. " appears",
            text_of(blocks[1]))
    end)

    it("marks punctuation-adjacent mentions", function()
        local blocks = postblocks.parse("(Brandon), said so", { username = "Brandon" })
        assert.equals(1, #blocks)
        assert.matches(postblocks.BOLD_START .. "Brandon" .. postblocks.BOLD_END, text_of(blocks[1]))
    end)

    it("marks mentions inside quotes too", function()
        local blocks = postblocks.parse("<blockquote>ping Brandon now</blockquote>", { username = "Brandon" })
        assert.matches(postblocks.BOLD_START .. "Brandon" .. postblocks.BOLD_END, blocks[1].text)
    end)

    it("flags quote headers that cite the user", function()
        local you = postblocks.parse("<blockquote><h4>Brandon posted:</h4>words</blockquote>",
            { username = "Brandon" })
        assert.is_truthy(you[1].mentions_you)
        local other = postblocks.parse("<blockquote><h4>Someone posted:</h4>words</blockquote>",
            { username = "Brandon" })
        assert.is_falsy(other[1].mentions_you)
    end)
end)

describe("postblocks collapsed_text", function()
    -- A minimal stand-in for a laid-out TextBoxWidget: charlist plus the
    -- wrapped-line list the real widget builds.
    local function fake_tbox(text, line_ends)
        local chars = {}
        for i = 1, #text do
            chars[i] = text:sub(i, i)
        end
        local lines = {}
        local start = 1
        for _, end_offset in ipairs(line_ends) do
            lines[#lines + 1] = { offset = start, end_offset = end_offset }
            start = end_offset + 1
        end
        return { charlist = chars, vertical_string_list = lines }
    end

    it("returns nil when the quote fits within the line budget", function()
        assert.is_nil(postblocks.collapsed_text(fake_tbox("ab\ncd", { 3, 6 }), 3))
        assert.is_nil(postblocks.collapsed_text({ vertical_string_list = {} }, 3))
        assert.is_nil(postblocks.collapsed_text(nil, 3))
    end)

    it("cuts at the last line boundary inside the budget and reports the remainder", function()
        local text = "aaa bbb ccc ddd"
        local prefix, remaining = postblocks.collapsed_text(
            fake_tbox(text, { 3, 7, 11, 15 }), 3)
        assert.equals("aaa bbb ccc", prefix)
        assert.equals(1, remaining)
    end)

    it("balances a bold run cut by the truncation", function()
        local marked = "xx " .. postblocks.BOLD_START .. "yy zz" .. postblocks.BOLD_END .. " tail"
        -- lines end inside the bold run, after it, and after the tail
        local prefix = postblocks.collapsed_text(
            fake_tbox(marked, { 3, 11, #marked - 5, #marked }), 2)
        assert.equals("xx " .. postblocks.BOLD_START .. "yy zz" .. postblocks.BOLD_END, prefix)
    end)
end)

describe("postblocks hostile input", function()
    it("degrades an unclosed blockquote to a quote block instead of truncating", function()
        local blocks = postblocks.parse("<blockquote><h4>x posted:</h4>never closed and more words")
        assert.equals(1, #blocks)
        assert.equals("quote", blocks[1].type)
        assert.matches("never closed and more words", blocks[1].text)
    end)

    it("keeps rendering after an unmatched blockquote mid-body", function()
        local blocks = postblocks.parse("before<blockquote>unclosed<blockquote>nested tail")
        assert.is_true(#blocks >= 1)
        local last = blocks[#blocks]
        assert.matches("nested tail", last.text)
    end)

    it("falls back to plain text when a body yields no blocks", function()
        local blocks = postblocks.parse("<div><span></span></div>")
        assert.equals(0, #blocks) -- all-empty content stays empty

        local nonempty = postblocks.parse("<div>words survive</div>")
        assert.equals(1, #nonempty)
        assert.matches("words survive", nonempty[1].text)
    end)

    it("parses classed blockquotes", function()
        local blocks = postblocks.parse('<blockquote class="bbc-block"><h4>x posted:</h4>words</blockquote>')
        assert.equals("quote", blocks[1].type)
        assert.equals("x posted:", blocks[1].header)
        assert.matches("words", blocks[1].text)
    end)
end)

-- The native view sanitizes before parsing (raw site HTML enters the
-- pipeline); this pins the whole raw-to-blocks path.
describe("postblocks on raw site HTML", function()
    it("produces the full block set when the view sanitizes first", function()
        local posthtml = require("saforums.posthtml")
        local raw = 'text<br><span class="bbc-spoiler">shh</span><br>'
            .. '<img src="https://i.fixture.invalid/p.png" alt="pic">'
            .. '<blockquote class="bbc-block"><h4>x posted:</h4>quoted</blockquote>'
        local blocks = postblocks.parse(posthtml.sanitize_body(raw))
        local kinds = {}
        for _i, block in ipairs(blocks) do
            kinds[#kinds + 1] = block.type
        end
        assert.same({ "para", "spoiler", "image", "quote" }, kinds)
    end)
end)
