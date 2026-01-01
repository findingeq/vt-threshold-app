# CLAUDE.md - AI Assistant Guidelines

## Project Overview
This is a Flutter iOS app (VT Threshold Analyzer) for real-time respiratory monitoring.

## Instructions for Claude

### 1. Evaluate Instructions Carefully
When the user provides any instructions, carefully evaluate whether they are logical and appropriate given the overall purpose of the app. If the instructions are not clear, ask clarifying questions before proceeding.

### 2. Always Ask Permission Before Coding
Do not code anything automatically. Always ask for permission first before making any code changes. Explain what you plan to do and wait for approval.

### 3. Preserve Existing Features
**CRITICAL**: Never remove, simplify, or overwrite existing functionality unless the user explicitly asks you to. This includes:
- UI features (tap-to-edit dialogs, manual input options, etc.)
- Visual design elements (colors, animations, backgrounds)
- Configuration options and their ranges
- Any behavior that currently exists in the codebase

When adding new features or making changes, ensure all existing functionality remains intact. If a change would affect existing features, explicitly ask the user before proceeding.

### 4. Update Version on Changes
When making code changes, always update the version in `pubspec.yaml`:
- The version format is `X.Y.Z+BUILD` (e.g., `1.0.0+10`)
- Increment the build number (+BUILD) for minor changes
- Increment the patch version (Z) for bug fixes
- Increment the minor version (Y) for new features
- Increment the major version (X) for breaking changes

### 5. iOS Build Environment
The user does not have a Mac. iOS builds are done using **Codemagic** (cloud CI/CD service). Keep this in mind when discussing:
- Build processes
- Testing on iOS
- Signing and deployment
- Any Mac-specific development steps

### 6. Explain Things Step-by-Step
The user is not a programmer. Always:
- Explain concepts in simple, non-technical terms
- Break down steps clearly
- Avoid assuming coding knowledge
- Provide context for why changes are needed
- Use analogies when helpful to explain technical concepts
