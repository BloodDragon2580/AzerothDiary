package main

import "testing"

func TestParseSavedVariables(t *testing.T) {
	src := `AzerothDiaryDB = { ["schemaVersion"] = 3, ["entries"] = { { ["id"] = 1, ["ts"] = 1788520000, ["kind"] = "manual", ["charKey"] = "Blood-Test", ["charName"] = "Blood", ["realm"] = "Test", ["zone"] = "Dornogal", ["data"] = { ["title"] = "Hallo", ["note"] = "Notiz\nZeile 2", }, }, [2] = { id=2, ts=1788521000, kind="level", charKey="Blood-Test", charName="Blood", data={ level=80, }, }, }, ["settings"]={ ["htmlWowheadTooltips"]=true }, }`
	root, err := ParseSavedVariables(src)
	if err != nil {
		t.Fatal(err)
	}
	d, err := diaryFromLua(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(d.Entries) != 2 {
		t.Fatalf("entries=%d", len(d.Entries))
	}
	if d.Entries[1].Data.GetString("note") != "Notiz\nZeile 2" {
		t.Fatalf("note=%q", d.Entries[1].Data.GetString("note"))
	}
	h := GenerateHTML(d, "de", true)
	if len(h) < 5000 {
		t.Fatalf("html too small: %d", len(h))
	}
}
