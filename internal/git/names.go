// Package git provides git repository operations including random branch name generation.
package git

import (
	"fmt"
	"math/rand"
	"time"
)

// Word lists for generating random branch names
var (
	colors = []string{
		"coral", "mint", "amber", "azure", "crimson", "emerald", "golden",
		"indigo", "jade", "lavender", "ruby", "sapphire", "silver", "violet",
		"bronze", "copper", "pearl", "rose", "slate", "teal",
	}

	adjectives = []string{
		"swift", "bold", "bright", "calm", "clever", "eager", "fierce", "gentle",
		"happy", "keen", "lively", "merry", "noble", "quick", "sharp", "steady",
		"strong", "wild", "wise", "brave", "cool", "fair", "kind", "neat",
		"pure", "rare", "safe", "true", "vast", "warm",
	}

	animals = []string{
		"zebra", "panda", "tiger", "eagle", "dolphin", "falcon", "gecko", "hawk",
		"iguana", "jaguar", "koala", "lemur", "meerkat", "narwhal", "octopus",
		"penguin", "quail", "raven", "seal", "turtle", "urchin", "viper",
		"walrus", "yak", "badger", "cheetah", "drake", "ferret", "lynx",
		"otter", "python", "shark", "wolf", "fox", "bear", "deer", "crane",
	}
)

// RandomBranchName generates a random branch name using the pattern: work/color-adjective-animal
// Example: work/coral-swift-zebra
func RandomBranchName() string {
	// Use current time as seed for better randomness
	r := rand.New(rand.NewSource(time.Now().UnixNano()))

	color := colors[r.Intn(len(colors))]
	adjective := adjectives[r.Intn(len(adjectives))]
	animal := animals[r.Intn(len(animals))]

	return fmt.Sprintf("work/%s-%s-%s", color, adjective, animal)
}

// GenerateUniqueBranchName generates a unique branch name by checking against existing branches
// It will try up to maxAttempts times before giving up
func (r *Repository) GenerateUniqueBranchName(maxAttempts int) (string, error) {
	if maxAttempts <= 0 {
		maxAttempts = 100 // Default to 100 attempts
	}

	for i := 0; i < maxAttempts; i++ {
		branchName := RandomBranchName()

		// Check if branch already exists
		if !r.BranchExists(branchName) {
			return branchName, nil
		}
	}

	return "", fmt.Errorf("failed to generate unique branch name after %d attempts", maxAttempts)
}
