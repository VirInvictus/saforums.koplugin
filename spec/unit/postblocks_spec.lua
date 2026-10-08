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

    it("turns image placeholders into image blocks", function()
        local blocks = postblocks.parse('hello<span class="imgref">[image: pic.png]</span>bye')
        assert.equals(3, #blocks)
        assert.equals("image", blocks[2].type)
        assert.equals("[image: pic.png]", blocks[2].label)
    end)

    it("returns no blocks for an empty body", function()
        assert.equals(0, #postblocks.parse(""))
        assert.equals(0, #postblocks.parse(nil))
    end)

    it("renders spoiler spans as marked plain text", function()
        local blocks = postblocks.parse('<span class="spoiler">[spoiler] shh [/spoiler]</span>')
        assert.matches("%[spoiler%] shh %[/spoiler%]", blocks[1].text)
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
end)
