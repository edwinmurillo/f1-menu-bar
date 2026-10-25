# F1 Menu Bar

Working title for a native macOS menu bar app that shows the next Formula 1 weekend, the season calendar and race winners, and driver and constructor championship points.

**Status: planning.** The project folder and documentation are ready. Application code, an Xcode project, and build scripts have not been created.

Read [PLAN.md](PLAN.md) for the proposed experience, verified API choice, implementation stages, and acceptance criteria. The working title and folder name are provisional.

## Proposed stack

- Swift 6 and SwiftUI, with a macOS 14 minimum deployment target.
- `MenuBarExtra` for the status bar panel; a regular window for Calendar, Drivers, and Constructors.
- XcodeGen as the project source of truth; Swift Package Manager if dependencies become necessary.
- OpenF1 over HTTPS using `URLSession`, with a small JSON disk cache and `UserDefaults` for preferences. Jolpica remains a verified alternative; see the API comparison in the plan.
- XCTest with injected time, fixture responses, and deterministic asynchronous tests.

## Project contents

- `PLAN.md`: product and engineering plan, API evidence, and delivery criteria.
- `AGENTS.md`: development guidance.
- `Claude.md`: symlink to the shared agent guidance.
- `.gitignore`: exclusions for the proposed native Swift toolchain.

## Setup and development

No dependencies need to be installed to review the plan. Implementation will require full Xcode and XcodeGen; their versions will be checked and recorded when the app is scaffolded.

Build, run, test, and formatting commands are not available yet. The first implementation stage will add repository-owned scripts and document their verified commands here. No API key or backend is planned for the initial version.

## Distribution

Start with a local macOS app. Packaging, signing, notarization, repository visibility, and the final name will be settled when distribution is in scope. OpenF1's free historical tier is intended for personal use; live access is paid. The plan includes the current OpenF1, Jolpica, and official calendar findings and the remaining integration checks.
