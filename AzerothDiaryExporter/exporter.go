package main

import (
	"fmt"
	"html"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type Entry struct {
	ID                                                   int64
	TS                                                   int64
	Kind, CharKey, CharName, Realm, Class, Zone, SubZone string
	Level                                                float64
	Data                                                 *LuaTable
}

type Diary struct {
	Entries  []Entry
	Settings *LuaTable
}

func diaryFromLua(root *LuaTable) (*Diary, error) {
	entriesTable := root.GetTable("entries")
	if entriesTable == nil {
		return nil, fmt.Errorf("SavedVariables enthalten keine 'entries'-Tabelle")
	}
	d := &Diary{Settings: root.GetTable("settings")}
	for _, raw := range entriesTable.Values() {
		t, ok := raw.(*LuaTable)
		if !ok {
			continue
		}
		e := Entry{ID: anyInt(t.Get("id")), TS: anyInt(t.Get("ts")), Kind: t.GetString("kind"), CharKey: t.GetString("charKey"), CharName: t.GetString("charName"), Realm: t.GetString("realm"), Class: t.GetString("class"), Zone: t.GetString("zone"), SubZone: t.GetString("subZone"), Level: t.GetFloat("level"), Data: t.GetTable("data")}
		if e.Data == nil {
			e.Data = newLuaTable()
		}
		if e.TS <= 0 {
			continue
		}
		d.Entries = append(d.Entries, e)
	}
	sort.SliceStable(d.Entries, func(i, j int) bool { return d.Entries[i].TS > d.Entries[j].TS })
	return d, nil
}

type labels struct {
	Lang, Kicker, Subtitle, Generated, Search, AllCategories, AllCharacters, Memories, ActiveDays, Characters, Today, Calendar, CalendarHint, Year, Month, Day, AllYears, AllMonths, AllDays, ClearDate, CalendarSelect, Page, PageNav, Prev, Next, NoResults, Footer string
	Kind                                                                                                                                                                                                                                                              map[string]string
}

func getLabels(lang string) labels {
	de := strings.HasPrefix(strings.ToLower(lang), "de")
	if de {
		return labels{Lang: "de", Kicker: "WORLD OF WARCRAFT • PERSÖNLICHE CHRONIK", Subtitle: "Deine persönliche Chronik aus World of Warcraft", Generated: "Erstellt am %s", Search: "Erinnerungen durchsuchen", AllCategories: "Alle Kategorien", AllCharacters: "Alle Charaktere", Memories: "Erinnerungen", ActiveDays: "Aktive Tage", Characters: "Charaktere", Today: "Heute", Calendar: "Kalender", CalendarHint: "Wähle Jahr, Monat oder einen markierten Tag, um zu sehen, was du damals erlebt hast.", Year: "Jahr", Month: "Monat", Day: "Tag", AllYears: "Alle Jahre", AllMonths: "Alle Monate", AllDays: "Alle Tage", ClearDate: "Datum zurücksetzen", CalendarSelect: "Wähle Jahr und Monat, um die Tage im Kalender anzuzeigen.", Page: "Seite", PageNav: "Seitennavigation des Tagebuchs", Prev: "Zurück", Next: "Weiter", NoResults: "Keine Erinnerungen entsprechen diesen Filtern.", Footer: "Erstellt mit Azeroth Diary für World of Warcraft", Kind: map[string]string{"achievement": "Erfolg", "mount": "Neues Reittier", "pet": "Neues Kampfhaustier", "toy": "Neues Spielzeug", "transmog": "Neue Transmog-Vorlage", "boss": "Boss besiegt", "mythicplus": "Mythic+-Bestleistung", "level": "Levelaufstieg", "gold": "Gold-Meilenstein", "itemlevel": "Itemlevel-Bestleistung", "quest": "Quest abgeschlossen", "manual": "Persönliche Erinnerung"}}
	}
	return labels{Lang: "en", Kicker: "WORLD OF WARCRAFT • PERSONAL CHRONICLE", Subtitle: "A personal chronicle from World of Warcraft", Generated: "Generated %s", Search: "Search memories", AllCategories: "All categories", AllCharacters: "All characters", Memories: "memories", ActiveDays: "Active days", Characters: "Characters", Today: "Today", Calendar: "Calendar", CalendarHint: "Choose a year, month, or highlighted day to see what you experienced then.", Year: "Year", Month: "Month", Day: "Day", AllYears: "All years", AllMonths: "All months", AllDays: "All days", ClearDate: "Clear date", CalendarSelect: "Choose a year and month to show the days in the calendar.", Page: "Page", PageNav: "Diary page navigation", Prev: "Previous", Next: "Next", NoResults: "No memories match these filters.", Footer: "Created with Azeroth Diary for World of Warcraft", Kind: map[string]string{"achievement": "Achievement", "mount": "New mount", "pet": "New battle pet", "toy": "New toy", "transmog": "New transmog", "boss": "Boss defeated", "mythicplus": "Mythic+ personal best", "level": "Level up", "gold": "Gold milestone", "itemlevel": "Item-level personal best", "quest": "Quest completed", "manual": "Personal memory"}}
}

func stripWoWFormatting(s string) string {
	// Lightweight removal of common color, hyperlink and texture wrappers.
	for {
		i := strings.Index(s, "|c")
		if i < 0 || i+10 > len(s) {
			break
		}
		s = s[:i] + s[i+10:]
	}
	s = strings.ReplaceAll(s, "|r", "")
	for {
		a := strings.Index(s, "|H")
		if a < 0 {
			break
		}
		b := strings.Index(s[a+2:], "|h")
		if b < 0 {
			break
		}
		b += a + 2
		c := strings.Index(s[b+2:], "|h")
		if c < 0 {
			break
		}
		c += b + 2
		label := s[b+2 : c]
		s = s[:a] + label + s[c+2:]
	}
	for {
		a := strings.Index(s, "|T")
		if a < 0 {
			break
		}
		b := strings.Index(s[a+2:], "|t")
		if b < 0 {
			break
		}
		b += a + 2
		s = s[:a] + s[b+2:]
	}
	return s
}
func esc(s string) string { return html.EscapeString(stripWoWFormatting(s)) }
func attr(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(esc(s), "\n", " "), "\r", " ")
}

func formatGold(copper float64) string {
	gold := int64(copper / 10000)
	if gold >= 1000000 {
		v := float64(gold) / 1e6
		if v >= 10 {
			return fmt.Sprintf("%.0fM", v)
		}
		return fmt.Sprintf("%.1fM", v)
	}
	if gold >= 1000 {
		v := float64(gold) / 1000
		if v >= 10 {
			return fmt.Sprintf("%.0fk", v)
		}
		return fmt.Sprintf("%.1fk", v)
	}
	return strconv.FormatInt(gold, 10)
}
func dataString(d *LuaTable, key string) string {
	if d == nil {
		return ""
	}
	return d.GetString(key)
}
func dataNum(d *LuaTable, key string) float64 {
	if d == nil {
		return 0
	}
	return d.GetFloat(key)
}
func dataBool(d *LuaTable, key string) bool {
	if d == nil {
		return false
	}
	v := d.Get(key)
	b, _ := v.(bool)
	return b
}

func entryTitle(e Entry, l labels) string {
	d := e.Data
	name := dataString(d, "name")
	switch e.Kind {
	case "achievement":
		if name != "" {
			return name
		}
		id := int64(dataNum(d, "id"))
		return fmt.Sprintf("Achievement #%d", id)
	case "mount":
		if name == "" {
			if l.Lang == "de" {
				name = "Unbekanntes Reittier"
			} else {
				name = "Unknown mount"
			}
		}
		if l.Lang == "de" {
			return name + " wurde deiner Sammlung hinzugefügt"
		}
		return name + " joined your collection"
	case "pet":
		if name == "" {
			if l.Lang == "de" {
				name = "Unbekanntes Kampfhaustier"
			} else {
				name = "Unknown battle pet"
			}
		}
		if l.Lang == "de" {
			return name + " wurde deiner Haustiersammlung hinzugefügt"
		}
		return name + " joined your pet collection"
	case "toy":
		if name == "" {
			if l.Lang == "de" {
				name = "Unbekanntes Spielzeug"
			} else {
				name = "Unknown toy"
			}
		}
		if l.Lang == "de" {
			return name + " wurde der Spielzeugkiste hinzugefügt"
		}
		return name + " added to the Toy Box"
	case "transmog":
		if name == "" {
			if l.Lang == "de" {
				name = "Neue Vorlage"
			} else {
				name = "New appearance"
			}
		}
		if l.Lang == "de" {
			return name + " wurde deinen Vorlagen hinzugefügt"
		}
		return name + " added to your appearances"
	case "boss":
		if name == "" {
			name = "Boss"
		}
		if l.Lang == "de" {
			return "Erster Sieg über " + name
		}
		return "First victory over " + name
	case "mythicplus":
		if name == "" {
			if l.Lang == "de" {
				name = "Mythic+-Dungeon"
			} else {
				name = "Mythic+ dungeon"
			}
		}
		return fmt.Sprintf("%s +%d", name, int(dataNum(d, "level")))
	case "level":
		if l.Lang == "de" {
			return fmt.Sprintf("Level %d erreicht", int(dataNum(d, "level")))
		}
		return fmt.Sprintf("Reached level %d", int(dataNum(d, "level")))
	case "gold":
		if l.Lang == "de" {
			return formatGold(dataNum(d, "amount")) + " Gold erreicht"
		}
		return "Reached " + formatGold(dataNum(d, "amount")) + " gold"
	case "itemlevel":
		if l.Lang == "de" {
			return fmt.Sprintf("Itemlevel %.1f erreicht", dataNum(d, "itemLevel"))
		}
		return fmt.Sprintf("Reached item level %.1f", dataNum(d, "itemLevel"))
	case "quest":
		if name != "" {
			return name
		}
		id := int(dataNum(d, "id"))
		if l.Lang == "de" {
			return fmt.Sprintf("Quest #%d", id)
		}
		return fmt.Sprintf("Quest #%d", id)
	case "manual":
		if s := dataString(d, "title"); s != "" {
			return s
		}
		return l.Kind["manual"]
	}
	if s := l.Kind[e.Kind]; s != "" {
		return s
	}
	return e.Kind
}
func entryDetail(e Entry, l labels) string {
	d := e.Data
	switch e.Kind {
	case "achievement":
		if l.Lang == "de" {
			return fmt.Sprintf("%d Erfolgspunkte", int(dataNum(d, "points")))
		}
		return fmt.Sprintf("%d achievement points", int(dataNum(d, "points")))
	case "boss":
		inst := dataString(d, "instance")
		if inst == "" {
			inst = e.Zone
		}
		diff := dataString(d, "difficulty")
		if diff == "" {
			if l.Lang == "de" {
				diff = "Unbekannter Schwierigkeitsgrad"
			} else {
				diff = "Unknown difficulty"
			}
		}
		return inst + " • " + diff
	case "mythicplus":
		suffix := ""
		if s := dataString(d, "durationText"); s != "" {
			suffix = " • " + s
		}
		if dataBool(d, "onTime") {
			if l.Lang == "de" {
				return "In der Zeit abgeschlossen" + suffix
			}
			return "Completed in time" + suffix
		}
		if l.Lang == "de" {
			return "Außerhalb der Zeit abgeschlossen" + suffix
		}
		return "Completed over time" + suffix
	case "quest":
		if l.Lang == "de" {
			return "Quest abgeschlossen"
		}
		return "Quest completed"
	case "manual":
		return dataString(d, "note")
	case "transmog":
		// WoW item hyperlinks contain an internal payload such as
		// |Hitem:175283:...|h[Item name]|h. The title already contains the
		// readable item name (and optionally the Wowhead link), so rendering
		// itemLink as a detail would either duplicate the name or leak the
		// raw hyperlink payload into the exported HTML.
		return ""
	}
	return dataString(d, "detail")
}

var icons = map[string]string{"achievement": "🏆", "mount": "🐉", "pet": "🐾", "toy": "🎁", "transmog": "✨", "boss": "⚔️", "mythicplus": "🗝️", "level": "📈", "gold": "💰", "itemlevel": "🛡️", "quest": "📜", "manual": "❤️"}

func wowheadInfo(e Entry, l labels) (href, data string, ok bool) {
	d := e.Data
	id := int64(0)
	page := ""
	switch e.Kind {
	case "achievement":
		id = int64(dataNum(d, "id"))
		page = "achievement"
	case "mount":
		id = int64(dataNum(d, "id"))
		page = "mount"
	case "pet":
		id = int64(dataNum(d, "speciesID"))
		page = "battle-pet"
	case "toy":
		id = int64(dataNum(d, "id"))
		page = "item"
	case "transmog":
		id = int64(dataNum(d, "itemID"))
		page = "item"
	case "quest":
		id = int64(dataNum(d, "id"))
		page = "quest"
	}
	if id <= 0 || page == "" {
		return "", "", false
	}
	host := "https://www.wowhead.com"
	if l.Lang == "de" {
		host = "https://de.wowhead.com"
	}
	if page == "mount" || page == "battle-pet" {
		href = fmt.Sprintf("%s/%s/%d", host, page, id)
	} else {
		href = fmt.Sprintf("%s/%s=%d", host, page, id)
	}
	data = fmt.Sprintf("%s=%d", page, id)
	if e.Kind == "achievement" {
		who := strings.NewReplacer("&", "", "=", "").Replace(e.CharName)
		if who != "" {
			data += "&who=" + who
		}
		data += fmt.Sprintf("&when=%d", e.TS*1000)
	}
	if l.Lang == "de" {
		data += "&domain=de"
	}
	return href, data, true
}

func formatDate(ts int64, l labels) string {
	t := time.Unix(ts, 0)
	if l.Lang == "de" {
		return t.Format("02.01.2006 • 15:04")
	}
	return t.Format("2006-01-02 • 15:04")
}

func GenerateHTML(d *Diary, lang string, useWowhead bool) string {
	l := getLabels(lang)
	now := time.Now()
	activeDays := map[string]bool{}
	chars := map[string]string{}
	cats := map[string]bool{}
	today := 0
	for _, e := range d.Entries {
		t := time.Unix(e.TS, 0)
		activeDays[t.Format("2006-01-02")] = true
		key := e.CharKey
		if key == "" {
			key = e.CharName
		}
		if key != "" {
			name := e.CharName
			if name == "" {
				name = key
			}
			if e.Realm != "" {
				name += " – " + e.Realm
			}
			chars[key] = name
		}
		cats[e.Kind] = true
		if sameDay(t, now) {
			today++
		}
	}
	type kv struct{ k, v string }
	var charList []kv
	for k, v := range chars {
		charList = append(charList, kv{k, v})
	}
	sort.Slice(charList, func(i, j int) bool { return strings.ToLower(charList[i].v) < strings.ToLower(charList[j].v) })
	var catList []string
	for k := range cats {
		catList = append(catList, k)
	}
	sort.Slice(catList, func(i, j int) bool { return l.Kind[catList[i]] < l.Kind[catList[j]] })
	var years []string
	ym := map[string]bool{}
	for _, e := range d.Entries {
		y := time.Unix(e.TS, 0).Format("2006")
		ym[y] = true
	}
	for y := range ym {
		years = append(years, y)
	}
	sort.Sort(sort.Reverse(sort.StringSlice(years)))
	var b strings.Builder
	w := func(s string) { b.WriteString(s) }
	w("<!DOCTYPE html><html lang=\"" + l.Lang + "\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Azeroth Diary</title>")
	if useWowhead {
		w(`<script>const whTooltips={colorLinks:false,iconizeLinks:false,renameLinks:false};</script><script src="https://wow.zamimg.com/js/tooltips.js"></script>`)
	}
	w(`<style>:root{color-scheme:dark;--bg:#080b12;--panel:#101625;--panel2:#161e30;--line:#28344e;--text:#eef2ff;--muted:#99a6c1;--gold:#d9ad5b;--blue:#69a7ff}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 15% 0,#17213a 0,#080b12 34%,#05070c 100%);color:var(--text);font-family:Inter,Segoe UI,Arial,sans-serif;min-height:100vh}.wrap{max-width:1180px;margin:auto;padding:42px 20px 70px}.hero{padding:34px;border:1px solid var(--line);border-radius:22px;background:linear-gradient(135deg,rgba(217,173,91,.10),rgba(105,167,255,.04)),rgba(16,22,37,.92)}h1{font-size:clamp(2.1rem,5vw,4rem);margin:0 0 8px;letter-spacing:-.04em}.tag{color:var(--gold);font-weight:700}.muted{color:var(--muted)}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:20px 0}.stat{padding:18px;border:1px solid var(--line);border-radius:16px;background:var(--panel)}.stat b{display:block;font-size:1.7rem;margin-top:4px}.tools{display:grid;grid-template-columns:2fr 1fr 1fr;gap:10px;margin:24px 0 12px}.tools input,.tools select,.calendar-controls select{width:100%;padding:13px 14px;border-radius:12px;border:1px solid var(--line);background:#0b1020;color:var(--text);font-size:1rem}.calendar{margin:0 0 24px;padding:18px;border:1px solid var(--line);border-radius:16px;background:rgba(16,22,37,.92)}.calendar-head{display:flex;align-items:center;justify-content:space-between;gap:16px;margin-bottom:14px}.calendar-title{font-weight:800;color:var(--gold);font-size:.82rem;letter-spacing:.08em;text-transform:uppercase}.calendar-subtitle{margin-top:3px;color:var(--muted);font-size:.9rem}.calendar-controls{display:grid;grid-template-columns:150px 180px 140px auto;gap:8px;align-items:center}.calendar-controls button{min-height:47px;padding:10px 14px;border:1px solid var(--line);border-radius:12px;background:var(--panel2);color:var(--text);cursor:pointer}.calendar-weekdays,.calendar-days{display:grid;grid-template-columns:repeat(7,1fr);gap:6px}.calendar-weekdays span{text-align:center;color:var(--muted);font-size:.74rem;font-weight:700;padding:4px}.calendar-days{margin-top:4px}.calendar-day{position:relative;min-height:54px;border:1px solid var(--line);border-radius:10px;background:#0b1020;color:var(--text);cursor:pointer;font-weight:700}.calendar-day:disabled{opacity:.22;cursor:default}.calendar-day.active{background:var(--gold);border-color:var(--gold);color:#111827}.calendar-day .count{position:absolute;right:6px;bottom:4px;font-size:.68rem;color:var(--muted)}.calendar-blank{min-height:54px}.calendar-message{grid-column:1/-1;text-align:center;padding:18px;color:var(--muted);border:1px dashed var(--line);border-radius:10px}.timeline{display:grid;gap:12px}.memory{display:grid;grid-template-columns:54px 1fr auto;gap:15px;align-items:start;padding:18px;border:1px solid var(--line);border-radius:16px;background:rgba(16,22,37,.92)}.memory[hidden]{display:none!important}.ico{display:grid;place-items:center;width:50px;height:50px;border-radius:14px;background:var(--panel2);font-size:1.55rem}.kind{font-size:.75rem;letter-spacing:.08em;text-transform:uppercase;color:var(--gold);font-weight:800}.memory h2{font-size:1.05rem;margin:4px 0}.wh-link{color:var(--gold);text-decoration:none;border-bottom:1px dotted rgba(217,173,91,.55)}.detail{color:var(--muted);line-height:1.5;white-space:pre-wrap}.where{margin-top:8px;color:#7f8da9;font-size:.86rem}.when{text-align:right;color:var(--muted);font-size:.84rem;white-space:nowrap}.char{color:var(--blue);font-weight:700;margin-top:5px}.empty{display:none;padding:40px;text-align:center;border:1px dashed var(--line);border-radius:16px;color:var(--muted)}.pager{display:flex;align-items:center;justify-content:center;gap:10px;flex-wrap:wrap;margin:24px 0 4px}.pager[hidden]{display:none!important}.pager button{min-width:44px;min-height:42px;padding:9px 13px;border:1px solid var(--line);border-radius:11px;background:var(--panel);color:var(--text);cursor:pointer}.page-numbers{display:flex;gap:6px;align-items:center;flex-wrap:wrap;justify-content:center}.page-numbers button.active{background:var(--gold);border-color:var(--gold);color:#111827;font-weight:800}.page-info{width:100%;text-align:center;color:var(--muted);font-size:.86rem}footer{margin-top:32px;text-align:center;color:#72809c}@media(max-width:760px){.wrap{padding:20px 12px 50px}.hero{padding:22px}.stats{grid-template-columns:repeat(2,1fr)}.tools{grid-template-columns:1fr}.calendar-head{align-items:flex-start;flex-direction:column}.calendar-controls{grid-template-columns:1fr 1fr}.calendar-controls button{grid-column:1/-1}.memory{grid-template-columns:44px 1fr}.ico{width:42px;height:42px}.when{grid-column:2;text-align:left}.calendar-day{min-height:46px;padding:2px}.calendar-day .count{font-size:.58rem}}</style></head><body><main class="wrap">`)
	w(`<section class="hero"><div class="tag">` + esc(l.Kicker) + `</div><h1>Azeroth Diary</h1><div class="muted">` + esc(l.Subtitle) + `</div><div class="muted" style="margin-top:8px">` + esc(fmt.Sprintf(l.Generated, formatDate(now.Unix(), l))) + `</div></section>`)
	w(`<section class="stats"><div class="stat"><span class="muted">` + esc(l.Memories) + `</span><b>` + strconv.Itoa(len(d.Entries)) + `</b></div><div class="stat"><span class="muted">` + esc(l.ActiveDays) + `</span><b>` + strconv.Itoa(len(activeDays)) + `</b></div><div class="stat"><span class="muted">` + esc(l.Characters) + `</span><b>` + strconv.Itoa(len(chars)) + `</b></div><div class="stat"><span class="muted">` + esc(l.Today) + `</span><b>` + strconv.Itoa(today) + `</b></div></section>`)
	w(`<section class="tools"><input id="q" type="search" placeholder="` + attr(l.Search) + `"><select id="cat"><option value="">` + esc(l.AllCategories) + `</option>`)
	for _, k := range catList {
		label := l.Kind[k]
		if label == "" {
			label = k
		}
		w(`<option value="` + attr(k) + `">` + esc(label) + `</option>`)
	}
	w(`</select><select id="char"><option value="">` + esc(l.AllCharacters) + `</option>`)
	for _, c := range charList {
		w(`<option value="` + attr(c.k) + `">` + esc(c.v) + `</option>`)
	}
	w(`</select></section>`)
	w(`<section class="calendar"><div class="calendar-head"><div><div class="calendar-title">` + esc(l.Calendar) + `</div><div class="calendar-subtitle">` + esc(l.CalendarHint) + `</div></div><div class="calendar-controls"><select id="year"><option value="">` + esc(l.AllYears) + `</option>`)
	for _, y := range years {
		w(`<option value="` + y + `">` + y + `</option>`)
	}
	w(`</select><select id="month"><option value="">` + esc(l.AllMonths) + `</option></select><select id="day" disabled><option value="">` + esc(l.AllDays) + `</option></select><button id="clearDate" type="button">` + esc(l.ClearDate) + `</button></div></div><div id="calendarWeekdays" class="calendar-weekdays"></div><div id="calendarDays" class="calendar-days"></div></section><section id="timeline" class="timeline">`)
	for _, e := range d.Entries {
		t := time.Unix(e.TS, 0)
		title := entryTitle(e, l)
		detail := entryDetail(e, l)
		loc := e.Zone
		if e.SubZone != "" && e.SubZone != loc {
			if loc != "" {
				loc += " • "
			}
			loc += e.SubZone
		}
		search := strings.Join([]string{title, detail, e.CharName, e.Realm, loc, l.Kind[e.Kind]}, " ")
		w(`<article class="memory" data-cat="` + attr(e.Kind) + `" data-char="` + attr(e.CharKey) + `" data-search="` + attr(search) + `" data-year="` + t.Format("2006") + `" data-month="` + t.Format("01") + `" data-day="` + t.Format("02") + `"><div class="ico">` + icons[e.Kind] + `</div><div><div class="kind">` + esc(l.Kind[e.Kind]) + `</div><h2>`)
		if useWowhead {
			if href, data, ok := wowheadInfo(e, l); ok {
				w(`<a class="wh-link" href="` + attr(href) + `" data-wowhead="` + attr(data) + `" target="_blank" rel="noopener noreferrer">` + esc(title) + `</a>`)
			} else {
				w(esc(title))
			}
		} else {
			w(esc(title))
		}
		w(`</h2>`)
		if detail != "" {
			w(`<div class="detail">` + esc(detail) + `</div>`)
		}
		w(`<div class="where">📍 ` + esc(loc) + `</div></div><div class="when">` + esc(formatDate(e.TS, l)) + `<div class="char">` + esc(e.CharName) + `</div></div></article>`)
	}
	w(`</section><div id="empty" class="empty">` + esc(l.NoResults) + `</div><nav id="pager" class="pager" aria-label="` + attr(l.PageNav) + `" hidden><button id="prevPage" type="button">` + esc(l.Prev) + `</button><div id="pageNumbers" class="page-numbers"></div><button id="nextPage" type="button">` + esc(l.Next) + `</button><div id="pageInfo" class="page-info"></div></nav><footer>` + esc(l.Footer) + `</footer></main>`)
	js := fmt.Sprintf(`<script>const q=document.getElementById('q'),cat=document.getElementById('cat'),chr=document.getElementById('char'),year=document.getElementById('year'),month=document.getElementById('month'),day=document.getElementById('day'),clearDate=document.getElementById('clearDate'),calendarWeekdays=document.getElementById('calendarWeekdays'),calendarDays=document.getElementById('calendarDays'),cards=[...document.querySelectorAll('.memory')],empty=document.getElementById('empty'),pager=document.getElementById('pager'),prevPage=document.getElementById('prevPage'),nextPage=document.getElementById('nextPage'),pageNumbers=document.getElementById('pageNumbers'),pageInfo=document.getElementById('pageInfo'),timeline=document.getElementById('timeline');const pageSize=20,pageLabel=%q,memoriesLabel=%q,allDaysLabel=%q,calendarSelectLabel=%q;let currentPage=1;const locale=document.documentElement.lang==='de'?'de-DE':'en-US';for(let number=1;number<=12;number++){const option=document.createElement('option');option.value=String(number).padStart(2,'0');option.textContent=new Intl.DateTimeFormat(locale,{month:'long'}).format(new Date(2026,number-1,1));month.appendChild(option)}function renderWeekdays(){calendarWeekdays.textContent='';const formatter=new Intl.DateTimeFormat(locale,{weekday:'short'});const monday=new Date(2026,0,5);for(let index=0;index<7;index++){const span=document.createElement('span'),d=new Date(monday);d.setDate(monday.getDate()+index);span.textContent=formatter.format(d);calendarWeekdays.appendChild(span)}}function matchesBase(el){const s=q.value.trim().toLocaleLowerCase(),c=cat.value,h=chr.value;return(s===''?true:(el.dataset.search||'').toLocaleLowerCase().includes(s))&&(c===''?true:el.dataset.cat===c)&&(h===''?true:el.dataset.char===h)}function matches(el){if(!matchesBase(el))return false;const y=year.value,m=month.value,d=day.value;return(y===''?true:el.dataset.year===y)&&(m===''?true:el.dataset.month===m)&&(d===''?true:el.dataset.day===d)}function rebuildDaySelect(){const selected=day.value;day.textContent='';const a=document.createElement('option');a.value='';a.textContent=allDaysLabel;day.appendChild(a);if(year.value!==''&&month.value!==''){const maxDay=new Date(Number(year.value),Number(month.value),0).getDate();for(let n=1;n<=maxDay;n++){const o=document.createElement('option');o.value=String(n).padStart(2,'0');o.textContent=String(n);day.appendChild(o)}day.disabled=false;if(selected!==''&&Number(selected)<=maxDay)day.value=selected}else{day.disabled=true;day.value=''}}function renderCalendar(){calendarDays.textContent='';if(!(year.value!==''&&month.value!=='')){const m=document.createElement('div');m.className='calendar-message';m.textContent=calendarSelectLabel;calendarDays.appendChild(m);return}const y=Number(year.value),m=Number(month.value),maxDay=new Date(y,m,0).getDate(),first=(new Date(y,m-1,1).getDay()+6)%%7;for(let blank=0;blank<first;blank++){const s=document.createElement('div');s.className='calendar-blank';calendarDays.appendChild(s)}const baseCards=cards.filter(matchesBase);for(let n=1;n<=maxDay;n++){const value=String(n).padStart(2,'0');let count=0;for(const el of baseCards){if(el.dataset.year===year.value&&el.dataset.month===month.value&&el.dataset.day===value)count++}const button=document.createElement('button');button.type='button';button.className='calendar-day'+(day.value===value?' active':'');button.disabled=count===0;button.innerHTML='<span>'+n+'</span><span class="count">'+count+'</span>';button.addEventListener('click',()=>{day.value=day.value===value?'':value;render(true)});calendarDays.appendChild(button)}}function addPageButton(n){const button=document.createElement('button');button.type='button';button.textContent=n;if(n===currentPage)button.className='active';button.addEventListener('click',()=>{currentPage=n;render(false);timeline.scrollIntoView({block:'start'})});pageNumbers.appendChild(button)}function renderPageNumbers(total){pageNumbers.textContent='';let start=Math.max(1,currentPage-2),finish=Math.min(total,start+4);start=Math.max(1,finish-4);if(start>1)addPageButton(1);for(let n=start;n<=finish;n++)addPageButton(n);if(finish<total)addPageButton(total)}function render(reset){if(reset)currentPage=1;const filtered=cards.filter(matches),totalPages=Math.max(1,Math.ceil(filtered.length/pageSize));if(currentPage>totalPages)currentPage=totalPages;for(const el of cards)el.hidden=true;if(filtered.length){const start=(currentPage-1)*pageSize,finish=Math.min(start+pageSize,filtered.length);for(let i=start;i<finish;i++)filtered[i].hidden=false}empty.style.display=filtered.length?'none':'block';pager.hidden=!filtered.length;if(filtered.length){prevPage.disabled=currentPage<=1;nextPage.disabled=currentPage>=totalPages;pageInfo.textContent=pageLabel+' '+currentPage+' / '+totalPages+' · '+filtered.length+' '+memoriesLabel;renderPageNumbers(totalPages)}renderCalendar()}q.addEventListener('input',()=>render(true));cat.addEventListener('change',()=>render(true));chr.addEventListener('change',()=>render(true));year.addEventListener('change',()=>{day.value='';rebuildDaySelect();render(true)});month.addEventListener('change',()=>{day.value='';rebuildDaySelect();render(true)});day.addEventListener('change',()=>render(true));clearDate.addEventListener('click',()=>{year.value='';month.value='';day.value='';rebuildDaySelect();render(true)});prevPage.addEventListener('click',()=>{if(currentPage>1){currentPage--;render(false)}});nextPage.addEventListener('click',()=>{const total=Math.max(1,Math.ceil(cards.filter(matches).length/pageSize));if(currentPage<total){currentPage++;render(false)}});renderWeekdays();rebuildDaySelect();render(true);</script>`, l.Page, l.Memories, l.AllDays, l.CalendarSelect)
	w(js)
	w(`</body></html>`)
	return b.String()
}
func sameDay(a, b time.Time) bool {
	ay, am, ad := a.Date()
	by, bm, bd := b.Date()
	return ay == by && am == bm && ad == bd
}

func ExportFile(source, output, lang string, useWowhead bool) (int, error) {
	raw, err := os.ReadFile(source)
	if err != nil {
		return 0, err
	}
	root, err := ParseSavedVariables(string(raw))
	if err != nil {
		return 0, err
	}
	d, err := diaryFromLua(root)
	if err != nil {
		return 0, err
	}
	htmlText := GenerateHTML(d, lang, useWowhead)
	if err := os.MkdirAll(filepath.Dir(output), 0755); err != nil {
		return 0, err
	}
	tmp := output + ".tmp"
	if err := os.WriteFile(tmp, []byte(htmlText), 0644); err != nil {
		return 0, err
	}
	if err := os.Rename(tmp, output); err != nil {
		_ = os.Remove(output)
		if err2 := os.Rename(tmp, output); err2 != nil {
			return 0, err2
		}
	}
	return len(d.Entries), nil
}
