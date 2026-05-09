# Lessons (auto-distilled + manually curated)

> Entries here outlive specific tasks. The dream cycle promotes recurring
> patterns from episodic into this file. Feel free to curate manually —
> delete bad lessons, tighten wording, reorganize sections.

## Seed lessons

- Always read `protocols/permissions.md` before any destructive tool call.
- Write the failing test before writing the fix.
- Log to episodic memory on every significant action, success or failure.
- When a skill has failed 3+ times in 14 days, propose a rewrite.
- Never force push to protected branches under any circumstance.

## Auto-promoted entries will be appended below

### 2026-05

- Include at least one dreamer teammate in non-trivial agent teams <!-- status=accepted confidence=0.7 evidence=0 id=lesson_4e385cf86f92 -->
- Team lead delegates aggressively — opus architects/plans/reviews, never reads or writes code or state files directly <!-- status=accepted confidence=0.7 evidence=0 id=lesson_233a72169c87 -->
- Implementation teammates work on branches with isolation: worktree; only the lead or user merges to main <!-- status=accepted confidence=0.7 evidence=0 id=lesson_e693fcce07e7 -->
- Implementation teammates report state changes; only dreamers write .dreams/ and .memories/ files <!-- status=accepted confidence=0.7 evidence=0 id=lesson_53e84a610a3c -->
- Temp files for inter-agent context sharing belong under .memories/tmp/, never /tmp/ or .scratch/ <!-- status=accepted confidence=0.7 evidence=0 id=lesson_6c709fa85557 -->
- For changes under 50 lines, use a single gemma4:26b call and skip the planning model <!-- status=accepted confidence=0.7 evidence=0 id=lesson_f378358e58a2 -->
- Embed exact type signatures and struct definitions in local-model prompts, not descriptions <!-- status=accepted confidence=0.7 evidence=0 id=lesson_71fa5b9c70a7 -->
- Request diff-format output from local code models for edits to existing files <!-- status=accepted confidence=0.7 evidence=0 id=lesson_7f91431fffac -->
- Orchestrators must strip markdown code fences from local-model output — every model adds them despite instructions <!-- status=accepted confidence=0.7 evidence=0 id=lesson_8187ae4a40d3 -->
- Orchestrators should fix trivial compile errors directly rather than re-dispatching to a local model <!-- status=accepted confidence=0.7 evidence=0 id=lesson_4690a9a5ab75 -->
- Never run parallel writes to the same file from multiple subagents <!-- status=accepted confidence=0.7 evidence=0 id=lesson_fc9f49ccbced -->
- Use stdin piping (cat | gemini --yolo) for multi-line gemini prompts; nix run wrapper mangles them <!-- status=accepted confidence=0.7 evidence=0 id=lesson_907dbb36761b -->
- Don't dispatch to gemini for review-only tasks — gemini may edit files unprompted <!-- status=accepted confidence=0.7 evidence=0 id=lesson_8a995013a7b1 -->
- Don't dispatch to gemini when opus already has full task context loaded <!-- status=accepted confidence=0.7 evidence=0 id=lesson_98e9f0153f28 -->
- Before marking a team's final task complete, ask 'What did this team learn that isn't in existing memories?' and save non-obvious findings <!-- status=accepted confidence=0.7 evidence=0 id=lesson_df68561d8e5d -->
- Haiku subagents have a summarization bias — instruct them to 'Return exact content verbatim, do not summarize or paraphrase' <!-- status=accepted confidence=0.7 evidence=0 id=lesson_41160abb67d7 -->
- Haiku subagents may write files unsolicited — instruct them 'Do not create, write, or modify any files' for read-only tasks <!-- status=accepted confidence=0.7 evidence=0 id=lesson_c3a256171871 -->
- Keep haiku prompts under 200 words — prompt length insensitivity degrades response quality <!-- status=accepted confidence=0.7 evidence=0 id=lesson_04cfa95d3504 -->
- Don't fan out to 4+ parallel haiku subagents for tasks under 100 tokens of work each — overhead dominates <!-- status=accepted confidence=0.7 evidence=0 id=lesson_dbaf22d7f9bf -->
- Sonnet subagents over-investigate by default — scope searches explicitly: 'Read file X, report fields Y and Z' <!-- status=accepted confidence=0.7 evidence=0 id=lesson_061d99bbba60 -->

### 2026-04

- Always serialize timestamps in UTC to avoid cross-region comparison bugs <!-- status=accepted confidence=0.46 evidence=1 id=lesson_422695ae5b2d -->
