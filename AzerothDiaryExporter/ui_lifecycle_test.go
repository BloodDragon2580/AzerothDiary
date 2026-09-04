package main

import (
	"testing"
	"time"
)

func newLifecycleTestApp() *App {
	return &App{
		quit:    make(chan struct{}),
		uiPages: make(map[string]time.Time),
	}
}

func TestScheduleUIShutdownClosesWithoutOpenPages(t *testing.T) {
	a := newLifecycleTestApp()
	a.scheduleUIShutdown(15 * time.Millisecond)
	select {
	case <-a.quit:
	case <-time.After(500 * time.Millisecond):
		t.Fatal("exporter did not quit after UI was closed")
	}
}

func TestScheduleUIShutdownKeepsRunningWithNewPage(t *testing.T) {
	a := newLifecycleTestApp()
	a.mu.Lock()
	a.uiPages["new-page"] = time.Now()
	a.mu.Unlock()
	a.scheduleUIShutdown(15 * time.Millisecond)
	select {
	case <-a.quit:
		t.Fatal("exporter quit although a new UI page was active")
	case <-time.After(80 * time.Millisecond):
	}
}

func TestRequestQuitIsIdempotent(t *testing.T) {
	a := newLifecycleTestApp()
	a.requestQuit()
	a.requestQuit()
	select {
	case <-a.quit:
	default:
		t.Fatal("quit channel should be closed")
	}
}
