package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestExportFileAndJavascript(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "AzerothDiary.lua")
	out := filepath.Join(dir, "AzerothDiary.html")
	data := `AzerothDiaryDB = {
["schemaVersion"] = 3,
["entries"] = {
    [1] = { ["id"] = 1, ["ts"] = 1788520000, ["kind"] = "achievement", ["charKey"] = "Blood-Testrealm", ["charName"] = "Blood", ["realm"] = "Testrealm", ["zone"] = "Dornogal", ["subZone"] = "Forgegrounds", ["data"] = { ["id"] = 12345, ["name"] = "A Test Achievement", ["points"] = 10, }, },
    [2] = { ["id"] = 2, ["ts"] = 1788521000, ["kind"] = "manual", ["charKey"] = "Blood-Testrealm", ["charName"] = "Blood", ["realm"] = "Testrealm", ["zone"] = "Dornogal", ["data"] = { ["title"] = "Raidabend", ["note"] = "War richtig gut & spaßig <3", }, },
},
["settings"] = { ["htmlWowheadTooltips"] = true, },
}`
	if err := os.WriteFile(src, []byte(data), 0644); err != nil {
		t.Fatal(err)
	}
	n, err := ExportFile(src, out, "de", true)
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Fatalf("entries=%d", n)
	}
	htmlBytes, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	h := string(htmlBytes)
	for _, needle := range []string{"Azeroth Diary", "data-year=", "calendarDays", "Raidabend", "War richtig gut &amp; spaßig &lt;3", "wowhead.com"} {
		if !strings.Contains(h, needle) {
			t.Fatalf("missing %q", needle)
		}
	}
	start := strings.LastIndex(h, "<script>")
	end := strings.LastIndex(h, "</script>")
	if start < 0 || end <= start {
		t.Fatal("main script not found")
	}
	js := h[start+len("<script>") : end]
	jsPath := filepath.Join(dir, "export.js")
	if err := os.WriteFile(jsPath, []byte(js), 0644); err != nil {
		t.Fatal(err)
	}
	if node, err := exec.LookPath("node"); err == nil {
		if output, err := exec.Command(node, "--check", jsPath).CombinedOutput(); err != nil {
			t.Fatalf("javascript syntax invalid: %v\n%s", err, output)
		}
	}
}

func TestTransmogRawItemLinkIsNotRendered(t *testing.T) {
	d := &Diary{Entries: []Entry{{
		ID: 1, TS: 1788520000, Kind: "transmog", CharKey: "Blood-Test", CharName: "Blood", Realm: "Test", Zone: "Valdrakken",
		Data: func() *LuaTable {
			tbl := newLuaTable()
			tbl.Str["name"] = "Helm der Rastari"
			tbl.Str["itemID"] = int64(175283)
			tbl.Str["itemLink"] = "|cff1eff00|Hitem:175283::::::::80:64:::::::|h[Helm der Rastari]|h|r"
			return tbl
		}(),
	}}}

	html := GenerateHTML(d, "de", true)
	if strings.Contains(html, "item:175283") {
		t.Fatalf("raw WoW item hyperlink leaked into HTML")
	}
	if !strings.Contains(html, "https://de.wowhead.com/item=175283") {
		t.Fatalf("expected Wowhead item link missing")
	}
	if !strings.Contains(html, "Helm der Rastari wurde deinen Vorlagen hinzugefügt") {
		t.Fatalf("expected readable transmog title missing")
	}
}
