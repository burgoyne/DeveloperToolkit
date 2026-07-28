# Developer Toolkit

This toolkit is where I collect the smaller utilities, templates, and workflows I build. Some projects will be GitHub Actions, some will be command-line tools or scripts, and some will be reusable patterns for CI/CD, documentation, release automation, infrastructure, and overall workflow automation.

This repository is only the catalog and examples hub. Most tools will live in their own repositories so they can have their own versions, releases, documentation, and issue tracking.

## Overview

The goal is to make useful engineering automation easier to find and combine. A tool might handle one part of a larger workflow, such as detecting changed projects, generating release notes, publishing documentation, or summarizing a deployment.

The individual tools should be useful on their own, but they should also work well as building blocks in a larger pipeline. This hub keeps track of what exists, what is planned, and where each project lives.

## Toolkit Categories

### Application Templates

Starter applications or installable project templates for common project shapes. These may cover application structure, configuration, quality checks, and deployment assumptions.

### CI/CD Workflows

Reusable workflows and pipeline examples that connect build, test, security scanning, documentation, release, and deployment steps.

### Documentation Tooling

Tools that generate, transform, validate, package, or publish engineering documentation without assuming every team uses the same documentation stack.

### Automation Utilities

Small scripts, command-line tools, and GitHub Actions for repeatable engineering tasks. These should solve focused problems and produce outputs that are easy to use from other tools.

## Project Catalog

These projects are planned unless their status says otherwise.

| Project | Category | Description | Delivery Format | Status |
| --- | --- | --- | --- | --- |
| Changed Projects | Automation Utility | Detects which applications, services, or repository areas were affected by a change. | CLI and GitHub Action | Planned |
| Pull Requests Since Last Release | Automation Utility | Collects GitHub pull requests merged since the last release. | CLI and GitHub Action | Planned |
| [Release Notes Generator](scripts/Documentation/GenerateReleaseNotes/README.md) | Documentation Tooling | Generates structured release note data from GitHub commits and merged pull requests between two refs. | PowerShell script | [Available](scripts/Documentation/GenerateReleaseNotes/GenerateReleaseNotes.ps1) |
| Documentation Publisher | Documentation Tooling | Packages and publishes generated documentation without depending on a specific documentation framework. | CLI and GitHub Action | Planned |
| [New Confluence Page](scripts/Confluence/NewPage/README.md) | Documentation Tooling | Creates a new Confluence Cloud page from a local storage markup file and moves it beneath an existing folder. | PowerShell script | [Available](scripts/Confluence/NewPage/NewConfluencePage.ps1) |
| [Append Confluence Page](scripts/Confluence/AppendPage/README.md) | Documentation Tooling | Adds local storage markup to an existing Confluence Cloud page as a new page version. | PowerShell script | [Available](scripts/Confluence/AppendPage/AppendConfluencePage.ps1) |
| Deployment Summary | Automation Utility | Produces a structured summary of a deployment, including version, environment, artifacts, status, and related metadata. | CLI and GitHub Action | Planned |
| Security Scan Results | Automation Utility | Runs Semgrep and Trivy scans against the codebase and writes the results to an output folder. | CLI and GitHub Action | Planned |


## Consulting

The tools in this catalog are free to use under the repository license. I also provide consulting for teams that need help combining these tools, adapting them to their environment, or building custom workflows around CI/CD, release automation, documentation, cloud infrastructure, and developer automation.

More information is available at [andreburgoyne.com](https://www.andreburgoyne.com).

## Security

See [SECURITY.md](SECURITY.md) for security reporting guidance.

## License

See [LICENSE](LICENSE).
