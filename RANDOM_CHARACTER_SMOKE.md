# Random Character Smoke

Test build: `feature/raw-unified-stage1`

Game install: `D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework`

1. Enter Training Mode and select any one of the 31 characters.
2. Start Combo Trial recording. The left-side list is the Atomic Action authority; the legacy live preview on the right is not an acceptance source.
3. Perform the same normal twice, such as `2MP, 2MP`. Confirm the left side shows two separate rows with the same Action ID and occurrences 1 and 2.
4. Perform any additional reasonable combo actions, then stop and save. Every Runtime Action occurrence must remain its own left-side row.
5. Confirm readable direct BCM variants are only display detail. A true no-direct case must show `Action <ID> [NO_DIRECT_BCM_BINDING]`.
6. Reload the saved combo.
7. Run DEMO and confirm Raw Input replay still works. Timeline fallback should remain available where it was already supported.
8. Reset, perform the combo manually, and confirm the strict Atomic detector passes.
9. Repeat with a randomly chosen second character if convenient.

If a step fails, provide:

`D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework\data\TrainingComboTrials_data\LastRawStage1Diagnostic.json`

Do not merge this branch into stable `master` until the smoke result is accepted.
