package ui

import (
	"testing"
)

func TestNewMainMenuModel(t *testing.T) {
	model := NewMainMenuModel()

	if model == nil {
		t.Fatal("NewMainMenuModel() returned nil")
	}

	if model.choice != ActionNone {
		t.Errorf("Initial choice = %v, want %v", model.choice, ActionNone)
	}

	if model.list.Items() == nil {
		t.Error("Menu items are nil")
	}

	// Verify we have the expected number of menu items
	expectedItemCount := 6 // List, New, Remove, Prune, Settings, Quit
	if len(model.list.Items()) != expectedItemCount {
		t.Errorf("Menu item count = %d, want %d", len(model.list.Items()), expectedItemCount)
	}
}

func TestMainMenuActions(t *testing.T) {
	actions := []MainMenuAction{
		ActionNone,
		ActionListWorktrees,
		ActionNewWorktree,
		ActionRemoveWorktree,
		ActionPruneWorktrees,
		ActionSettings,
		ActionQuit,
	}

	// Just verify the constants are distinct
	seen := make(map[MainMenuAction]bool)
	for _, action := range actions {
		if seen[action] {
			t.Errorf("Duplicate action value: %v", action)
		}
		seen[action] = true
	}
}
