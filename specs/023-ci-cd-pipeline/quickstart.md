# Quickstart Validation Guide: Adapt CI/CD Pipeline

This guide explains how to validate the modified CI/CD workflows after implementation.

## Validation Scenarios

### 1. Validate PR and Push Triggers (`run_foss_spec.yml`, `size-limit.yml`)

**Prerequisites:**
- The CI pipeline updates must be committed to the `023-ci-cd-pipeline` branch.

**Steps:**
1. Push the branch to the origin repository.
2. Open a Pull Request targeting the `ichatr-main` branch.
3. Observe the "Checks" section of the Pull Request on GitHub.

**Expected Outcomes:**
- The `run_foss_spec` workflow (including `backend-tests`, `frontend-tests`, `lint-backend`, `lint-frontend`) is triggered and runs successfully.
- The `size-limit` workflow is triggered and runs successfully.
- The `lint_pr` and `test_docker_build` workflows are triggered and run successfully.

### 2. Validate Docker Publishing Workflow (`publish_ee_docker.yml`)

**Prerequisites:**
- The `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets must be configured in the repository settings.
- The feature branch must be merged into `ichatr-main`.

**Steps:**
1. Create a git tag on the `ichatr-main` branch (e.g., `4.16.2-ichatr.1`).
   ```bash
   git tag 4.16.2-ichatr.1
   git push origin 4.16.2-ichatr.1
   ```
2. Navigate to the GitHub Actions tab in the repository.

**Expected Outcomes:**
- The `Docker Image Build and Publish` workflow is triggered exclusively by the tag push.
- The workflow completes successfully without errors.
- The `edneymatias/ichatr` repository on Docker Hub lists the new `4.16.2-ichatr.1` tag and the updated `latest` tag.

### 3. Verify Deleted Workflows

**Prerequisites:**
- None.

**Steps:**
1. Navigate to the `Actions` tab on GitHub.
2. Attempt to trigger or find any of the deleted workflows (e.g., `publish_foss_docker.yml`, `deploy_check.yml`).

**Expected Outcomes:**
- The workflows are no longer listed or active.
- Only the 5 expected workflows exist in the `.github/workflows` directory of the `ichatr-main` branch.
