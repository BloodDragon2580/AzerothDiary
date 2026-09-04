package main

import (
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"
)

const version = "1.0.2"

//go:embed icon.png
var appIconPNG []byte

type Config struct {
	Source    string `json:"source"`
	Output    string `json:"output"`
	Language  string `json:"language"`
	Wowhead   bool   `json:"wowhead"`
	Auto      bool   `json:"auto"`
	OpenAfter bool   `json:"openAfter"`
}

type SourceInfo struct {
	Path  string `json:"path"`
	Label string `json:"label"`
}

type Status struct {
	Title   string `json:"title"`
	Message string `json:"message"`
	OK      bool   `json:"ok"`
}

type App struct {
	mu        sync.RWMutex
	cfg       Config
	sources   []SourceInfo
	status    Status
	cfgPath   string
	lastMod   time.Time
	lastSize  int64
	server    *http.Server
	quit      chan struct{}
	liveCount int
	liveEpoch uint64
}

func main() {
	app := newApp()
	defer app.closeLog()
	app.refreshSources()
	app.startWatcher()

	mux := http.NewServeMux()
	app.routes(mux)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatal(err)
	}
	app.server = &http.Server{Handler: mux}
	url := "http://" + ln.Addr().String() + "/"
	go func() {
		if err := app.server.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Printf("server: %v", err)
		}
	}()
	time.Sleep(120 * time.Millisecond)
	_ = openURL(url)
	<-app.quit
	_ = app.server.Close()
}

func newApp() *App {
	base, _ := os.UserConfigDir()
	if base == "" {
		base = os.TempDir()
	}
	dir := filepath.Join(base, "AzerothDiaryExporter")
	_ = os.MkdirAll(dir, 0755)
	logFile, _ := os.OpenFile(filepath.Join(dir, "exporter.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if logFile != nil {
		log.SetOutput(logFile)
	}
	cfg := Config{
		Language: defaultLanguage(),
		Output:   filepath.Join(userDocuments(), "Azeroth Diary", "AzerothDiary.html"),
		Wowhead:  true,
	}
	a := &App{
		cfg:     cfg,
		cfgPath: filepath.Join(dir, "config.json"),
		status:  Status{Title: "Bereit", Message: "Exporter gestartet.", OK: true},
		quit:    make(chan struct{}),
	}
	a.loadConfig()
	return a
}

func (a *App) closeLog() {}

func userDocuments() string {
	home, _ := os.UserHomeDir()
	if runtime.GOOS == "windows" {
		if p := os.Getenv("USERPROFILE"); p != "" {
			home = p
		}
	}
	return filepath.Join(home, "Documents")
}

func defaultLanguage() string {
	for _, v := range []string{os.Getenv("LANG"), os.Getenv("LC_ALL"), os.Getenv("LANGUAGE")} {
		if strings.HasPrefix(strings.ToLower(v), "de") {
			return "de"
		}
	}
	if runtime.GOOS == "windows" {
		out, _ := exec.Command("powershell.exe", "-NoProfile", "-Command", "[System.Globalization.CultureInfo]::CurrentUICulture.Name").Output()
		if strings.HasPrefix(strings.ToLower(strings.TrimSpace(string(out))), "de") {
			return "de"
		}
	}
	return "en"
}

func (a *App) loadConfig() {
	b, err := os.ReadFile(a.cfgPath)
	if err == nil {
		_ = json.Unmarshal(b, &a.cfg)
	}
	if a.cfg.Output == "" {
		a.cfg.Output = filepath.Join(userDocuments(), "Azeroth Diary", "AzerothDiary.html")
	}
	if a.cfg.Language != "de" && a.cfg.Language != "en" {
		a.cfg.Language = defaultLanguage()
	}
}

func (a *App) saveConfig() {
	a.mu.RLock()
	b, _ := json.MarshalIndent(a.cfg, "", "  ")
	a.mu.RUnlock()
	_ = os.WriteFile(a.cfgPath, b, 0644)
}

func (a *App) routes(mux *http.ServeMux) {
	mux.HandleFunc("/icon.png", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/png")
		w.Header().Set("Cache-Control", "public, max-age=86400")
		_, _ = w.Write(appIconPNG)
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = io.WriteString(w, webUI)
	})
	mux.HandleFunc("/api/state", a.stateHandler)
	mux.HandleFunc("/api/live", a.liveHandler)
	mux.HandleFunc("/api/config", a.configHandler)
	mux.HandleFunc("/api/refresh", a.refreshHandler)
	mux.HandleFunc("/api/export", a.exportHandler)
	mux.HandleFunc("/api/open-output", a.openOutputHandler)
	mux.HandleFunc("/api/open-folder", a.openFolderHandler)
	mux.HandleFunc("/api/pick-source", a.pickSourceHandler)
	mux.HandleFunc("/api/pick-output", a.pickOutputHandler)
	mux.HandleFunc("/api/quit", a.quitHandler)
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, err error) {
	w.WriteHeader(http.StatusBadRequest)
	writeJSON(w, map[string]string{"error": err.Error()})
}

func (a *App) liveHandler(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unavailable", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	a.mu.Lock()
	a.liveCount++
	a.liveEpoch++
	a.mu.Unlock()
	_, _ = io.WriteString(w, "event: ready\ndata: ok\n\n")
	flusher.Flush()
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()
	defer func() {
		a.mu.Lock()
		a.liveCount--
		a.liveEpoch++
		epoch := a.liveEpoch
		count := a.liveCount
		a.mu.Unlock()
		if count == 0 {
			go func(expected uint64) {
				time.Sleep(5 * time.Second)
				a.mu.RLock()
				stillClosed := a.liveCount == 0 && a.liveEpoch == expected
				a.mu.RUnlock()
				if stillClosed {
					select {
					case <-a.quit:
					default:
						close(a.quit)
					}
				}
			}(epoch)
		}
	}()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-ticker.C:
			_, _ = io.WriteString(w, ": keepalive\n\n")
			flusher.Flush()
		}
	}
}

func (a *App) stateHandler(w http.ResponseWriter, r *http.Request) {
	a.mu.RLock()
	defer a.mu.RUnlock()
	writeJSON(w, map[string]any{"version": version, "config": a.cfg, "sources": a.sources, "status": a.status})
}

func (a *App) configHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		writeErr(w, fmt.Errorf("POST required"))
		return
	}
	var c Config
	if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
		writeErr(w, err)
		return
	}
	if c.Language != "de" && c.Language != "en" {
		c.Language = "de"
	}
	a.mu.Lock()
	a.cfg = c
	a.mu.Unlock()
	a.saveConfig()
	writeJSON(w, map[string]bool{"ok": true})
}

func (a *App) refreshHandler(w http.ResponseWriter, r *http.Request) {
	a.refreshSources()
	a.mu.RLock()
	defer a.mu.RUnlock()
	writeJSON(w, map[string]any{"sources": a.sources})
}

func (a *App) exportHandler(w http.ResponseWriter, r *http.Request) {
	n, err := a.doExport(true)
	if err != nil {
		a.setStatus("Export fehlgeschlagen", err.Error(), false)
		writeErr(w, err)
		return
	}
	writeJSON(w, map[string]any{"ok": true, "entries": n})
}

func (a *App) openOutputHandler(w http.ResponseWriter, r *http.Request) {
	a.mu.RLock()
	p := a.cfg.Output
	a.mu.RUnlock()
	if _, err := os.Stat(p); err != nil {
		writeErr(w, fmt.Errorf("HTML noch nicht vorhanden: %s", p))
		return
	}
	if err := openPath(p); err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, map[string]bool{"ok": true})
}

func (a *App) openFolderHandler(w http.ResponseWriter, r *http.Request) {
	a.mu.RLock()
	p := filepath.Dir(a.cfg.Output)
	a.mu.RUnlock()
	_ = os.MkdirAll(p, 0755)
	if err := openFolder(p); err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, map[string]bool{"ok": true})
}

func (a *App) pickSourceHandler(w http.ResponseWriter, r *http.Request) {
	p, err := pickFile()
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, map[string]string{"path": p})
}

func (a *App) pickOutputHandler(w http.ResponseWriter, r *http.Request) {
	a.mu.RLock()
	cur := a.cfg.Output
	a.mu.RUnlock()
	p, err := pickSaveFile(cur)
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, map[string]string{"path": p})
}

func (a *App) quitHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]bool{"ok": true})
	select {
	case <-a.quit:
	default:
		close(a.quit)
	}
}

func (a *App) setStatus(title, msg string, ok bool) {
	a.mu.Lock()
	a.status = Status{Title: title, Message: msg, OK: ok}
	a.mu.Unlock()
}

func (a *App) doExport(manual bool) (int, error) {
	a.mu.RLock()
	c := a.cfg
	a.mu.RUnlock()
	if strings.TrimSpace(c.Source) == "" {
		return 0, fmt.Errorf("Bitte zuerst eine AzerothDiary.lua auswählen")
	}
	if strings.TrimSpace(c.Output) == "" {
		return 0, fmt.Errorf("Bitte eine Ziel-Datei angeben")
	}
	if !strings.HasSuffix(strings.ToLower(c.Output), ".html") {
		c.Output += ".html"
		a.mu.Lock()
		a.cfg.Output = c.Output
		a.mu.Unlock()
		a.saveConfig()
	}
	n, err := ExportFile(c.Source, c.Output, c.Language, c.Wowhead)
	if err != nil {
		return 0, err
	}
	a.setStatus("Export erfolgreich", fmt.Sprintf("%d Erinnerungen exportiert: %s", n, c.Output), true)
	if manual && c.OpenAfter {
		_ = openPath(c.Output)
	}
	return n, nil
}

func (a *App) startWatcher() {
	go func() {
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				a.watchTick()
			case <-a.quit:
				return
			}
		}
	}()
}

func (a *App) watchTick() {
	a.mu.RLock()
	c := a.cfg
	a.mu.RUnlock()
	if !c.Auto || c.Source == "" {
		return
	}
	st, err := os.Stat(c.Source)
	if err != nil {
		return
	}
	if a.lastMod.IsZero() {
		a.lastMod = st.ModTime()
		a.lastSize = st.Size()
		return
	}
	if st.ModTime() != a.lastMod || st.Size() != a.lastSize {
		a.lastMod = st.ModTime()
		a.lastSize = st.Size()
		time.Sleep(1200 * time.Millisecond)
		if n, err := a.doExport(false); err != nil {
			a.setStatus("Auto-Export fehlgeschlagen", err.Error(), false)
		} else {
			a.setStatus("Auto-Export erfolgreich", fmt.Sprintf("WoW-Daten geändert – %d Erinnerungen neu exportiert.", n), true)
		}
	}
}

func (a *App) refreshSources() {
	sources := detectSources()
	a.mu.Lock()
	a.sources = sources
	if a.cfg.Source == "" && len(sources) > 0 {
		a.cfg.Source = sources[0].Path
	}
	a.mu.Unlock()
	a.saveConfig()
}

func detectSources() []SourceInfo {
	seen := map[string]bool{}
	var roots []string
	add := func(p string) {
		p = strings.TrimSpace(strings.Trim(p, "\""))
		key := strings.ToLower(p)
		if p != "" && !seen[key] {
			seen[key] = true
			roots = append(roots, p)
		}
	}

	if runtime.GOOS == "windows" {
		for _, key := range []string{
			`HKLM\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft`,
			`HKLM\SOFTWARE\Blizzard Entertainment\World of Warcraft`,
			`HKCU\SOFTWARE\Blizzard Entertainment\World of Warcraft`,
		} {
			out, _ := exec.Command("reg.exe", "query", key, "/v", "InstallPath").Output()
			for _, line := range strings.Split(string(out), "\n") {
				if strings.Contains(line, "REG_SZ") {
					parts := strings.Fields(line)
					if len(parts) >= 3 {
						add(strings.Join(parts[2:], " "))
					}
				}
			}
		}
		for _, env := range []string{"ProgramFiles(x86)", "ProgramFiles"} {
			if p := os.Getenv(env); p != "" {
				add(filepath.Join(p, "World of Warcraft"))
			}
		}
		for _, drive := range []string{"C:", "D:", "E:", "F:", "G:"} {
			add(filepath.Join(drive+`\`, "Games", "World of Warcraft"))
			add(filepath.Join(drive+`\`, "World of Warcraft"))
		}
	}

	var out []SourceInfo
	for _, root := range roots {
		retail := root
		if filepath.Base(strings.TrimRight(root, `\/`)) != "_retail_" {
			retail = filepath.Join(root, "_retail_")
		}
		pattern := filepath.Join(retail, "WTF", "Account", "*", "SavedVariables", "AzerothDiary.lua")
		matches, _ := filepath.Glob(pattern)
		for _, m := range matches {
			account := ""
			parts := strings.Split(filepath.Clean(m), string(os.PathSeparator))
			for i := 0; i < len(parts); i++ {
				if strings.EqualFold(parts[i], "Account") && i+1 < len(parts) {
					account = parts[i+1]
					break
				}
			}
			label := account
			if label == "" {
				label = filepath.Base(filepath.Dir(filepath.Dir(m)))
			}
			label += " — " + m
			out = append(out, SourceInfo{Path: m, Label: label})
		}
	}

	sort.Slice(out, func(i, j int) bool {
		return strings.ToLower(out[i].Label) < strings.ToLower(out[j].Label)
	})
	dedup := out[:0]
	seen2 := map[string]bool{}
	for _, s := range out {
		k := strings.ToLower(filepath.Clean(s.Path))
		if !seen2[k] {
			seen2[k] = true
			dedup = append(dedup, s)
		}
	}
	return dedup
}

func openURL(url string) error {
	if runtime.GOOS == "windows" {
		return exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
	}
	return exec.Command("xdg-open", url).Start()
}

func openPath(path string) error {
	if runtime.GOOS == "windows" {
		return exec.Command("rundll32", "url.dll,FileProtocolHandler", path).Start()
	}
	return exec.Command("xdg-open", path).Start()
}

func openFolder(path string) error {
	if runtime.GOOS == "windows" {
		return exec.Command("explorer.exe", path).Start()
	}
	return exec.Command("xdg-open", path).Start()
}

func pickFile() (string, error) {
	if runtime.GOOS != "windows" {
		return "", fmt.Errorf("Dateiauswahl ist nur unter Windows verfügbar")
	}
	script := `Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.OpenFileDialog; $d.Filter='Azeroth Diary SavedVariables (AzerothDiary.lua)|AzerothDiary.lua|Lua files (*.lua)|*.lua|All files (*.*)|*.*'; if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding=[Text.UTF8Encoding]::UTF8; Write-Output $d.FileName}`
	out, err := exec.Command("powershell.exe", "-STA", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script).Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func pickSaveFile(current string) (string, error) {
	if runtime.GOOS != "windows" {
		return "", fmt.Errorf("Dateiauswahl ist nur unter Windows verfügbar")
	}
	dir := filepath.Dir(current)
	name := filepath.Base(current)
	escPS := func(s string) string { return strings.ReplaceAll(s, "'", "''") }
	script := fmt.Sprintf(`Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.SaveFileDialog; $d.Filter='HTML file (*.html)|*.html'; $d.DefaultExt='html'; $d.AddExtension=$true; $d.InitialDirectory='%s'; $d.FileName='%s'; if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding=[Text.UTF8Encoding]::UTF8; Write-Output $d.FileName}`, escPS(dir), escPS(name))
	out, err := exec.Command("powershell.exe", "-STA", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script).Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}
