local ADDON_NAME, AD = ...

local function stripWoWFormatting(value)
    value = tostring(value or "")
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("|H.-|h(.-)|h", "%1")
    value = value:gsub("|T.-|t", "")
    return value
end

local function htmlEscape(value)
    value = stripWoWFormatting(value)
    value = value:gsub("&", "&amp;")
    value = value:gsub("<", "&lt;")
    value = value:gsub(">", "&gt;")
    value = value:gsub('"', "&quot;")
    value = value:gsub("'", "&#39;")
    return value
end

local function attrEscape(value)
    return htmlEscape(value):gsub("\n", " "):gsub("\r", " ")
end


local function positiveInteger(value)
    value = tonumber(value)
    if not value or value <= 0 then return nil end
    return math.floor(value)
end

local function getWowheadTarget(entry)
    local d = entry and entry.data or {}
    if not entry then return nil end

    if entry.kind == "achievement" then
        local id = positiveInteger(d.id)
        if id then return "achievement", id, "achievement=" .. id end
    elseif entry.kind == "mount" then
        local id = positiveInteger(d.id)
        if id then return "mount", id, "mount=" .. id end
    elseif entry.kind == "pet" then
        local id = positiveInteger(d.speciesID)
        if id then return "battle-pet", id, "battle-pet=" .. id end
    elseif entry.kind == "toy" then
        local id = positiveInteger(d.id)
        if id then return "item", id, "item=" .. id end
    elseif entry.kind == "transmog" then
        local id = positiveInteger(d.itemID)
        if id then return "item", id, "item=" .. id end
    elseif entry.kind == "quest" then
        local id = positiveInteger(d.id)
        if id then return "quest", id, "quest=" .. id end
    end
    return nil
end

local function wowheadLink(entry, label, language)
    local pageType, id, tooltipData = getWowheadTarget(entry)
    if not pageType then return htmlEscape(label) end

    local isGerman = language == "de"
    local host = isGerman and "https://de.wowhead.com" or "https://www.wowhead.com"
    local href
    if pageType == "mount" or pageType == "battle-pet" then
        href = host .. "/" .. pageType .. "/" .. id
    else
        href = host .. "/" .. pageType .. "=" .. id
    end

    if entry.kind == "achievement" then
        local who = tostring(entry.charName or ""):gsub("[&=]", "")
        if who ~= "" then
            tooltipData = tooltipData .. "&who=" .. who
        end
        if tonumber(entry.ts) then
            tooltipData = tooltipData .. "&when=" .. tostring(math.floor(tonumber(entry.ts) * 1000))
        end
    end
    if isGerman then
        tooltipData = tooltipData .. "&domain=de"
    end

    return "<a class=\"wh-link\" href=\"" .. attrEscape(href) .. "\" data-wowhead=\"" .. attrEscape(tooltipData) .. "\" target=\"_blank\" rel=\"noopener noreferrer\">" .. htmlEscape(label) .. "</a>"
end

local HTML_ICONS = {
    achievement = "🏆",
    mount = "🐉",
    pet = "🐾",
    toy = "🎁",
    transmog = "✨",
    boss = "⚔️",
    mythicplus = "🗝️",
    level = "📈",
    gold = "💰",
    itemlevel = "🛡️",
    quest = "📜",
    manual = "❤️",
}

function AD:GenerateHTML(currentCharacterOnly, useWowhead)
    local entries = self:GetFilteredEntries("all", currentCharacterOnly, "")
    local stats = self:GetOverviewStats(currentCharacterOnly)
    local chunks = {}
    local function add(s) chunks[#chunks + 1] = s end

    local language = self:GetLanguage() == "deDE" and "de" or "en"
    useWowhead = useWowhead == true
    local generated = self:FormatDate(time(), true)
    local title = self:L("HTML_TITLE")
    local subtitle = self:L("HTML_SUBTITLE")

    local characters, seenChars = {}, {}
    local categories, seenKinds = {}, {}
    for _, entry in ipairs(entries) do
        if entry.charKey and not seenChars[entry.charKey] then
            seenChars[entry.charKey] = true
            characters[#characters + 1] = { key = entry.charKey, name = entry.charName or entry.charKey, realm = entry.realm }
        end
        if not seenKinds[entry.kind] then
            seenKinds[entry.kind] = true
            categories[#categories + 1] = entry.kind
        end
    end
    table.sort(characters, function(a, b) return (a.name or "") < (b.name or "") end)
    table.sort(categories, function(a, b) return self:GetKindLabel(a) < self:GetKindLabel(b) end)

    add("<!DOCTYPE html><html lang=\"" .. language .. "\"><head><meta charset=\"utf-8\">")
    add("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>" .. htmlEscape(title) .. "</title>")
    if useWowhead then
        -- Official Wowhead tooltip loader. The diary and its filters still work if this remote script is unavailable.
        add([[<script>const whTooltips={colorLinks:false,iconizeLinks:false,renameLinks:false};</script><script src="https://wow.zamimg.com/js/tooltips.js"></script>]])
    end
    add([[<style>
:root{color-scheme:dark;--bg:#080b12;--panel:#101625;--panel2:#161e30;--line:#28344e;--text:#eef2ff;--muted:#99a6c1;--gold:#d9ad5b;--blue:#69a7ff;--violet:#9a7cff;--green:#73d39b}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 15% 0,#17213a 0,#080b12 34%,#05070c 100%);color:var(--text);font-family:Inter,Segoe UI,Arial,sans-serif;min-height:100vh}.wrap{max-width:1180px;margin:auto;padding:42px 20px 70px}.hero{padding:34px;border:1px solid var(--line);border-radius:22px;background:linear-gradient(135deg,rgba(217,173,91,.10),rgba(105,167,255,.04)),rgba(16,22,37,.92)}h1{font-size:clamp(2.1rem,5vw,4rem);margin:0 0 8px;letter-spacing:-.04em}.tag{color:var(--gold);font-weight:700}.muted{color:var(--muted)}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:20px 0}.stat{padding:18px;border:1px solid var(--line);border-radius:16px;background:var(--panel)}.stat b{display:block;font-size:1.7rem;margin-top:4px}.tools{display:grid;grid-template-columns:2fr 1fr 1fr;gap:10px;margin:24px 0}.tools input,.tools select{width:100%;padding:13px 14px;border-radius:12px;border:1px solid var(--line);background:#0b1020;color:var(--text);font-size:1rem}.timeline{display:grid;gap:12px}.memory{display:grid;grid-template-columns:54px 1fr auto;gap:15px;align-items:start;padding:18px;border:1px solid var(--line);border-radius:16px;background:rgba(16,22,37,.92)}.memory[hidden]{display:none!important}.ico{display:grid;place-items:center;width:50px;height:50px;border-radius:14px;background:var(--panel2);font-size:1.55rem}.kind{font-size:.75rem;letter-spacing:.08em;text-transform:uppercase;color:var(--gold);font-weight:800}.memory h2{font-size:1.05rem;margin:4px 0}.wh-link{color:var(--gold);text-decoration:none;border-bottom:1px dotted rgba(217,173,91,.55)}.wh-link:hover,.wh-link:focus{color:#f3ca7a;border-bottom-color:#f3ca7a}.detail{color:var(--muted);line-height:1.5;white-space:pre-wrap}.where{margin-top:8px;color:#7f8da9;font-size:.86rem}.when{text-align:right;color:var(--muted);font-size:.84rem;white-space:nowrap}.char{color:var(--blue);font-weight:700;margin-top:5px}.empty{display:none;padding:40px;text-align:center;border:1px dashed var(--line);border-radius:16px;color:var(--muted)}.pager{display:flex;align-items:center;justify-content:center;gap:10px;flex-wrap:wrap;margin:24px 0 4px}.pager[hidden]{display:none!important}.pager button{min-width:44px;min-height:42px;padding:9px 13px;border:1px solid var(--line);border-radius:11px;background:var(--panel);color:var(--text);font-size:.92rem;cursor:pointer}.pager button:hover:not(:disabled),.pager button:focus-visible{border-color:var(--gold);color:var(--gold)}.pager button:disabled{opacity:.38;cursor:not-allowed}.page-numbers{display:flex;gap:6px;align-items:center;flex-wrap:wrap;justify-content:center}.page-numbers button.active{background:var(--gold);border-color:var(--gold);color:#111827;font-weight:800}.page-ellipsis{color:var(--muted);padding:0 2px}.page-info{width:100%;text-align:center;color:var(--muted);font-size:.86rem;margin-top:2px}footer{margin-top:32px;text-align:center;color:#72809c;font-size:.85rem}@media(max-width:760px){.stats{grid-template-columns:1fr 1fr}.tools{grid-template-columns:1fr}.memory{grid-template-columns:46px 1fr}.when{grid-column:2;text-align:left}.hero{padding:24px}.pager{gap:7px}.pager button{padding:8px 11px}}@media(max-width:420px){.stats{grid-template-columns:1fr}.wrap{padding:20px 12px 50px}}
</style></head><body><main class="wrap">]])

    add("<section class=\"hero\"><div class=\"tag\">" .. htmlEscape(self:L("HTML_KICKER")) .. "</div><h1>" .. htmlEscape(title) .. "</h1><p>" .. htmlEscape(subtitle) .. "</p><div class=\"muted\">" .. htmlEscape(self:L("HTML_GENERATED", generated)) .. "</div></section>")
    add("<section class=\"stats\">")
    add("<div class=\"stat\"><span class=\"muted\">" .. htmlEscape(self:L("TOTAL_MEMORIES")) .. "</span><b>" .. stats.total .. "</b></div>")
    add("<div class=\"stat\"><span class=\"muted\">" .. htmlEscape(self:L("ACTIVE_DAYS")) .. "</span><b>" .. stats.activeDaysCount .. "</b></div>")
    add("<div class=\"stat\"><span class=\"muted\">" .. htmlEscape(self:L("CHARACTERS")) .. "</span><b>" .. stats.characterCount .. "</b></div>")
    add("<div class=\"stat\"><span class=\"muted\">" .. htmlEscape(self:L("TODAY")) .. "</span><b>" .. stats.today .. "</b></div></section>")

    add("<section class=\"tools\"><input id=\"q\" type=\"search\" placeholder=\"" .. attrEscape(self:L("HTML_SEARCH")) .. "\" aria-label=\"" .. attrEscape(self:L("HTML_SEARCH")) .. "\">")
    add("<select id=\"cat\" aria-label=\"" .. attrEscape(self:L("HTML_CATEGORY")) .. "\"><option value=\"\">" .. htmlEscape(self:L("HTML_ALL_CATEGORIES")) .. "</option>")
    for _, kind in ipairs(categories) do
        add("<option value=\"" .. attrEscape(kind) .. "\">" .. htmlEscape(self:GetKindLabel(kind)) .. "</option>")
    end
    add("</select><select id=\"char\" aria-label=\"" .. attrEscape(self:L("HTML_CHARACTER")) .. "\"><option value=\"\">" .. htmlEscape(self:L("HTML_ALL_CHARACTERS")) .. "</option>")
    for _, char in ipairs(characters) do
        local charLabel = char.name .. ((char.realm and char.realm ~= "") and (" — " .. char.realm) or "")
        add("<option value=\"" .. attrEscape(char.key) .. "\">" .. htmlEscape(charLabel) .. "</option>")
    end
    add("</select></section><section id=\"timeline\" class=\"timeline\">")

    for _, entry in ipairs(entries) do
        local titleText = self:GetEntryTitle(entry)
        local detail = self:GetEntryDetail(entry)
        local location = entry.zone or ""
        if entry.subZone and entry.subZone ~= "" and entry.subZone ~= location then
            location = location .. " • " .. entry.subZone
        end
        local searchBlob = table.concat({ titleText or "", detail or "", entry.charName or "", entry.realm or "", location, self:GetKindLabel(entry.kind) or "" }, " ")
        add("<article class=\"memory\" data-cat=\"" .. attrEscape(entry.kind) .. "\" data-char=\"" .. attrEscape(entry.charKey or "") .. "\" data-search=\"" .. attrEscape(searchBlob) .. "\">")
        local titleHTML = useWowhead and wowheadLink(entry, titleText, language) or htmlEscape(titleText)
        add("<div class=\"ico\">" .. (HTML_ICONS[entry.kind] or "📖") .. "</div><div><div class=\"kind\">" .. htmlEscape(self:GetKindLabel(entry.kind)) .. "</div><h2>" .. titleHTML .. "</h2>")
        if detail and detail ~= "" then add("<div class=\"detail\">" .. htmlEscape(detail) .. "</div>") end
        add("<div class=\"where\">📍 " .. htmlEscape(location) .. "</div></div><div class=\"when\">" .. htmlEscape(self:FormatDate(entry.ts, true)) .. "<div class=\"char\">" .. htmlEscape(entry.charName or entry.charKey or "") .. "</div></div></article>")
    end

    add("</section><div id=\"empty\" class=\"empty\">" .. htmlEscape(self:L("HTML_NO_RESULTS")) .. "</div>")
    add("<nav id=\"pager\" class=\"pager\" aria-label=\"" .. attrEscape(self:L("HTML_PAGE_NAV")) .. "\" hidden><button id=\"prevPage\" type=\"button\">" .. htmlEscape(self:L("PREVIOUS")) .. "</button><div id=\"pageNumbers\" class=\"page-numbers\"></div><button id=\"nextPage\" type=\"button\">" .. htmlEscape(self:L("NEXT")) .. "</button><div id=\"pageInfo\" class=\"page-info\" aria-live=\"polite\"></div></nav>")
    add("<footer>" .. htmlEscape(self:L("HTML_FOOTER")) .. "</footer></main>")
    -- Important: avoid JavaScript logical OR (double pipe) in exported text. WoW EditBox can collapse doubled pipe characters while copying.
    add([[<script>
const q=document.getElementById('q'),cat=document.getElementById('cat'),chr=document.getElementById('char'),cards=[...document.querySelectorAll('.memory')],empty=document.getElementById('empty'),pager=document.getElementById('pager'),prevPage=document.getElementById('prevPage'),nextPage=document.getElementById('nextPage'),pageNumbers=document.getElementById('pageNumbers'),pageInfo=document.getElementById('pageInfo'),timeline=document.getElementById('timeline');
const pageSize=20,pageLabel=]] .. string.format('%q', self:L("HTML_PAGE")) .. [[,memoriesLabel=]] .. string.format('%q', self:L("HTML_MEMORIES")) .. [[;let currentPage=1;
function matches(el){const s=q.value.trim().toLocaleLowerCase(),c=cat.value,h=chr.value;const rawSearch=el.dataset.search?el.dataset.search:'';const searchOk=s===''?true:rawSearch.toLocaleLowerCase().includes(s);const categoryOk=c===''?true:el.dataset.cat===c;const characterOk=h===''?true:el.dataset.char===h;return searchOk&&categoryOk&&characterOk}
function addPageButton(number){const button=document.createElement('button');button.type='button';button.textContent=number;button.setAttribute('aria-label',pageLabel+' '+number);if(number===currentPage){button.className='active';button.setAttribute('aria-current','page')}button.addEventListener('click',function(){currentPage=number;render(false);timeline.scrollIntoView({block:'start'})});pageNumbers.appendChild(button)}
function addEllipsis(){const span=document.createElement('span');span.className='page-ellipsis';span.textContent='…';span.setAttribute('aria-hidden','true');pageNumbers.appendChild(span)}
function renderPageNumbers(totalPages){pageNumbers.textContent='';let start=Math.max(1,currentPage-2),finish=Math.min(totalPages,start+4);start=Math.max(1,finish-4);if(start>1){addPageButton(1);if(start>2)addEllipsis()}for(let number=start;number<=finish;number++)addPageButton(number);if(finish<totalPages){if(finish<totalPages-1)addEllipsis();addPageButton(totalPages)}}
function render(resetPage){if(resetPage)currentPage=1;const filtered=cards.filter(matches);const totalPages=Math.max(1,Math.ceil(filtered.length/pageSize));if(currentPage>totalPages)currentPage=totalPages;for(const el of cards)el.hidden=true;if(filtered.length>0){const start=(currentPage-1)*pageSize,finish=Math.min(start+pageSize,filtered.length);for(let index=start;index<finish;index++)filtered[index].hidden=false}const hasResults=filtered.length>0;empty.style.display=hasResults?'none':'block';pager.hidden=!hasResults;if(hasResults){prevPage.disabled=currentPage<=1;nextPage.disabled=currentPage>=totalPages;pageInfo.textContent=pageLabel+' '+currentPage+' / '+totalPages+' · '+filtered.length+' '+memoriesLabel;renderPageNumbers(totalPages)}}
q.addEventListener('input',function(){render(true)});cat.addEventListener('change',function(){render(true)});chr.addEventListener('change',function(){render(true)});prevPage.addEventListener('click',function(){if(currentPage>1){currentPage--;render(false);timeline.scrollIntoView({block:'start'})}});nextPage.addEventListener('click',function(){const filtered=cards.filter(matches),totalPages=Math.max(1,Math.ceil(filtered.length/pageSize));if(currentPage<totalPages){currentPage++;render(false);timeline.scrollIntoView({block:'start'})}});render(true);
</script></body></html>]])

    return table.concat(chunks), #entries
end
