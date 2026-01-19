package jira

import (
	"context"
	"fmt"
	"strings"

	"github.com/kaeawc/auto-worktree/internal/git"
	"github.com/kaeawc/auto-worktree/internal/providers"
)

// Provider implements the providers.Provider interface for JIRA
type Provider struct {
	client *Client
}

// NewProvider creates a new JIRA provider
func NewProvider(server, project string) (*Provider, error) {
	client, err := NewClient(server, project)
	if err != nil {
		return nil, err
	}

	return &Provider{
		client: client,
	}, nil
}

// NewProviderWithExecutor creates a JIRA provider with custom executor (for testing)
func NewProviderWithExecutor(server, project string, executor Executor) (*Provider, error) {
	client, err := NewClientWithExecutor(server, project, executor)
	if err != nil {
		return nil, err
	}

	return &Provider{
		client: client,
	}, nil
}

// Name returns the provider name
func (p *Provider) Name() string {
	return "JIRA"
}

// ProviderType returns the provider type for configuration
func (p *Provider) ProviderType() string {
	return "jira"
}

// ListIssues returns all open issues assigned to the current user
func (p *Provider) ListIssues(ctx context.Context, limit int) ([]providers.Issue, error) {
	jiraIssues, err := p.client.ListOpenIssues(ctx)
	if err != nil {
		return nil, err
	}

	// Convert to providers.Issue format
	capacity := len(jiraIssues)
	if limit > 0 && limit < capacity {
		capacity = limit
	}

	issues := make([]providers.Issue, 0, capacity)

	for i := range jiraIssues {
		issue := providers.Issue{
			ID:        jiraIssues[i].Key,
			Key:       jiraIssues[i].Key,
			Title:     jiraIssues[i].Fields.Summary,
			Body:      jiraIssues[i].Fields.Description,
			URL:       jiraIssues[i].Fields.URL,
			State:     jiraIssues[i].Fields.Status.Name,
			Labels:    jiraIssues[i].Fields.Labels,
			Author:    jiraIssues[i].Fields.Creator.DisplayName,
			CreatedAt: jiraIssues[i].Fields.Created,
			UpdatedAt: jiraIssues[i].Fields.Updated,
			Assignee:  jiraIssues[i].Fields.Assignee.DisplayName,
			IsClosed:  jiraIssues[i].IsClosed(),
		}
		issues = append(issues, issue)

		// Respect limit if specified
		if limit > 0 && len(issues) >= limit {
			break
		}
	}

	return issues, nil
}

// GetIssue returns details for a specific JIRA issue
func (p *Provider) GetIssue(ctx context.Context, id string) (*providers.Issue, error) {
	jiraIssue, err := p.client.GetIssue(ctx, id)
	if err != nil {
		return nil, err
	}

	return &providers.Issue{
		ID:        jiraIssue.Key,
		Key:       jiraIssue.Key,
		Title:     jiraIssue.Fields.Summary,
		Body:      jiraIssue.Fields.Description,
		URL:       jiraIssue.Fields.URL,
		State:     jiraIssue.Fields.Status.Name,
		Labels:    jiraIssue.Fields.Labels,
		Author:    jiraIssue.Fields.Creator.DisplayName,
		CreatedAt: jiraIssue.Fields.Created,
		UpdatedAt: jiraIssue.Fields.Updated,
		Assignee:  jiraIssue.Fields.Assignee.DisplayName,
		IsClosed:  jiraIssue.IsClosed(),
	}, nil
}

// IsIssueClosed returns true if a JIRA issue is closed/resolved
func (p *Provider) IsIssueClosed(ctx context.Context, id string) (bool, error) {
	isClosed, err := p.client.GetIssueStatus(ctx, id)

	return isClosed, err
}

// ListMilestones returns all open epics (JIRA's equivalent of milestones)
func (p *Provider) ListMilestones(ctx context.Context, limit int) ([]providers.Milestone, error) {
	epics, err := p.client.ListOpenEpics(ctx)
	if err != nil {
		return nil, err
	}

	capacity := len(epics)
	if limit > 0 && limit < capacity {
		capacity = limit
	}

	milestones := make([]providers.Milestone, 0, capacity)
	for i := range epics {
		milestones = append(milestones, providers.Milestone{
			ID:          epics[i].Key,
			Title:       epics[i].Fields.Summary,
			Description: epics[i].Fields.Description,
			State:       epics[i].Fields.Status.Name,
		})

		if limit > 0 && len(milestones) >= limit {
			break
		}
	}

	return milestones, nil
}

// ListIssuesByMilestone returns issues linked to a specific epic
func (p *Provider) ListIssuesByMilestone(ctx context.Context, milestoneID string, limit int) ([]providers.Issue, error) {
	jiraIssues, err := p.client.ListIssuesByEpic(ctx, milestoneID)
	if err != nil {
		return nil, err
	}

	capacity := len(jiraIssues)
	if limit > 0 && limit < capacity {
		capacity = limit
	}

	issues := make([]providers.Issue, 0, capacity)
	for i := range jiraIssues {
		issues = append(issues, providers.Issue{
			ID:        jiraIssues[i].Key,
			Key:       jiraIssues[i].Key,
			Title:     jiraIssues[i].Fields.Summary,
			Body:      jiraIssues[i].Fields.Description,
			URL:       jiraIssues[i].Fields.URL,
			State:     jiraIssues[i].Fields.Status.Name,
			Labels:    jiraIssues[i].Fields.Labels,
			Author:    jiraIssues[i].Fields.Creator.DisplayName,
			CreatedAt: jiraIssues[i].Fields.Created,
			UpdatedAt: jiraIssues[i].Fields.Updated,
			Assignee:  jiraIssues[i].Fields.Assignee.DisplayName,
			IsClosed:  jiraIssues[i].IsClosed(),
		})

		if limit > 0 && len(issues) >= limit {
			break
		}
	}

	return issues, nil
}

// MilestoneTerminology returns "Epic" for JIRA
func (p *Provider) MilestoneTerminology() string {
	return "Epic"
}

// ListPullRequests is not applicable for JIRA
func (p *Provider) ListPullRequests(_ context.Context, _ int) ([]providers.PullRequest, error) {
	return nil, fmt.Errorf("JIRA does not have pull requests")
}

// GetPullRequest is not applicable for JIRA
func (p *Provider) GetPullRequest(_ context.Context, _ string) (*providers.PullRequest, error) {
	return nil, fmt.Errorf("JIRA does not have pull requests")
}

// IsPullRequestMerged is not applicable for JIRA
func (p *Provider) IsPullRequestMerged(_ context.Context, _ string) (bool, error) {
	return false, fmt.Errorf("JIRA does not have pull requests")
}

// CreateIssue creates a new JIRA issue
func (p *Provider) CreateIssue(ctx context.Context, title, body string) (*providers.Issue, error) {
	jiraIssue, err := p.client.CreateIssue(ctx, title, body)
	if err != nil {
		return nil, err
	}

	return &providers.Issue{
		ID:        jiraIssue.Key,
		Key:       jiraIssue.Key,
		Title:     jiraIssue.Fields.Summary,
		Body:      jiraIssue.Fields.Description,
		URL:       jiraIssue.Fields.URL,
		State:     jiraIssue.Fields.Status.Name,
		Labels:    jiraIssue.Fields.Labels,
		Author:    jiraIssue.Fields.Creator.DisplayName,
		CreatedAt: jiraIssue.Fields.Created,
		UpdatedAt: jiraIssue.Fields.Updated,
		Assignee:  jiraIssue.Fields.Assignee.DisplayName,
		IsClosed:  jiraIssue.IsClosed(),
	}, nil
}

// CreatePullRequest is not applicable for JIRA
func (p *Provider) CreatePullRequest(_ context.Context, _, _, _, _ string) (*providers.PullRequest, error) {
	return nil, fmt.Errorf("JIRA does not support pull requests")
}

// GetBranchNameSuffix returns the JIRA key for use in branch names
func (p *Provider) GetBranchNameSuffix(issue *providers.Issue) string {
	return issue.Key
}

// SanitizeBranchName sanitizes a title for use in branch names
func (p *Provider) SanitizeBranchName(title string) string {
	// Convert to lowercase
	title = strings.ToLower(title)

	// Truncate to 40 characters
	if len(title) > 40 {
		title = title[:40]
	}

	// Use git.SanitizeBranchName for consistent sanitization
	return git.SanitizeBranchName(title)
}
