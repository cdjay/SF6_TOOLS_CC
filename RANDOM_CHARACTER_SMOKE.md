# Random Character Smoke

Test build: `feature/raw-unified-stage1`

Game install: `D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework`

1. Enter Training Mode and select any one of the 31 characters.
2. Start Combo Trial recording and perform any reasonable combo.
3. Stop and save. Confirm every Atomic Action appears as its own left-side row.
4. Confirm readable direct BCM variants are shown. A true no-direct case must show `Action <ID> [NO_DIRECT_BCM_BINDING]`.
5. Reload the saved combo.
6. Run DEMO and confirm Raw Input replay still works. Timeline fallback should remain available where it was already supported.
7. Reset, perform the combo manually, and confirm the strict Atomic detector passes.
8. Repeat with a randomly chosen second character if convenient.

If a step fails, provide:

`D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework\data\TrainingComboTrials_data\LastRawStage1Diagnostic.json`

Do not merge this branch into stable `master` until the smoke result is accepted.
