const flags = ['empty', 'changed', 'end', 'not_add', 'not_whole'];
const fields = ['size', 'index', 'type', ...flags].map(n => 'display_meter_' + n);

// Shared fresh-cell contract. A visible retained blue/green cell is not current state.
export function meterCell(rows, i, ix, side) {
  const get = (r, n) => r?.[ix[n]], p = (r, n) => get(r, `p${side}.${n}`);
  const r = rows[i], before = rows[i - 1];
  const out = Object.fromEntries(fields.map(n => [n, p(r, n)]));
  const contiguous = before && r && ['round', 'battle_round'].every(n => get(before, n) === get(r, n))
    && ['replay_frame', 'stage_frame'].every(n => get(r, n) === get(before, n) + 1);
  let status;
  if (!contiguous) status = 'no_contiguous_predecessor';
  else if (get(r, 'display_prev_frame') !== get(r, 'stage_frame')) status = 'display_clock_mismatch';
  else if (out.display_meter_size !== 80 || !Number.isInteger(out.display_meter_index)
    || out.display_meter_index < 0 || out.display_meter_index >= 80
    || !Number.isInteger(out.display_meter_type) || out.display_meter_type < 0 || out.display_meter_type > 14
    || flags.some(n => ![0, 1].includes(out['display_meter_' + n]))) status = 'unavailable_or_unknown_cell';
  else if (get(before, 'display_prev_frame') !== get(before, 'stage_frame')
    || p(before, 'display_meter_size') !== 80 || !Number.isInteger(p(before, 'display_meter_index'))
    || p(before, 'display_meter_index') < 0 || p(before, 'display_meter_index') >= 80
    || !Number.isSafeInteger(get(r, 'meter_start_frame')) || !Number.isSafeInteger(get(before, 'meter_start_frame'))) status = 'unavailable_predecessor';
  else if (get(before, 'meter_start_frame') !== get(r, 'meter_start_frame')) status = 'meter_reset';
  else if (p(before, 'display_meter_index') === out.display_meter_index) status = 'held_cursor';
  else if (out.display_meter_empty || out.display_meter_not_add || out.display_meter_not_whole) status = 'excluded_cell_flags';
  else if (out.display_meter_index !== (p(before, 'display_meter_index') + 1) % 80) status = 'cursor_jump';
  else status = 'advanced_cell';
  return { ...out, status };
}
