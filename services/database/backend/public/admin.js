// Verhalten der Admin-Seiten (beer.css + htmx). Alles läuft über data-Attribute der Diet-Templates und über
// Event-Delegation am document: htmx (hx-boost) tauscht den Seiteninhalt aus, die Listener bleiben gültig.
(function () {
  if (window.hdbAdmin) return; // einmal je Dokument, auch wenn htmx Skripte erneut sieht
  window.hdbAdmin = true;

  const byId = (id) => document.getElementById(id);

  function setNull(index, isNull) {
    const rowForm = byId('row-form');
    const field = rowForm.querySelector(`[data-field="${index}"]`);
    const box = rowForm.querySelector(`[data-null="${index}"]`);
    box.checked = isNull;
    field.disabled = isNull;
  }

  // Einfügen (values fehlt) und Bearbeiten teilen sich denselben Dialog.
  function openRowDialog(values, matchJson) {
    const rowForm = byId('row-form');
    const editing = values !== null;
    rowForm.action = editing ? rowForm.dataset.update : rowForm.dataset.insert;
    byId('row-match').value = matchJson || '';
    byId('row-title').textContent = editing ? 'Edit row' : 'Add row';
    byId('row-duplicate-note').classList.toggle('hidden', !editing);
    rowForm.querySelectorAll('[data-field]').forEach((field) => {
      const index = Number(field.dataset.field);
      const value = editing ? values[index] : '';
      field.value = value === null ? '' : value;
      setNull(index, value === null);
    });
    byId('row_modal').showModal();
  }

  document.addEventListener('click', (event) => {
    const target = event.target.closest('button');
    if (!target) return;
    if (target.dataset.resetUser) {
      const name = target.dataset.resetUser;
      byId('reset-form').action = `/admin/users/${encodeURIComponent(name)}/password`;
      byId('reset-title').textContent = `Reset password for ${name}`;
      byId('reset_modal').showModal();
    }
    // Rollen: Anlegen und Bearbeiten teilen sich einen Dialog; der Name einer bestehenden Rolle bleibt fest
    if (target.dataset.roleNew !== undefined || target.dataset.roleEdit) {
      const editing = Boolean(target.dataset.roleEdit);
      const granted = editing ? target.dataset.rolePermissions.split(' ') : [];
      const name = byId('role-name');
      name.value = editing ? target.dataset.roleEdit : '';
      name.readOnly = editing;
      byId('role-description').value = editing ? target.dataset.roleDescription : '';
      byId('role-title').textContent = editing ? `Edit role ${target.dataset.roleEdit}` : 'New role';
      document.querySelectorAll('#role-form [data-permission]').forEach((box) => {
        box.checked = granted.includes(box.dataset.permission);
      });
      byId('role_modal').showModal();
    }
    if (target.dataset.rowInsert) openRowDialog(null, '');
    if (target.dataset.rowEdit) {
      const json = target.closest('tr').dataset.values;
      openRowDialog(JSON.parse(json), json);
    }
    if (target.dataset.addColumn) {
      const list = byId('column-list');
      const row = list.querySelector('[data-column-row]').cloneNode(true);
      row.querySelector('input').value = '';
      list.appendChild(row);
      row.querySelector('input').focus();
    }
    if (target.dataset.removeColumn) {
      const list = byId('column-list');
      if (list.children.length > 1) target.closest('[data-column-row]').remove();
    }
  });

  document.addEventListener('change', (event) => {
    const { target } = event;
    if (target.dataset.null !== undefined) setNull(target.dataset.null, target.checked);
    // requestSubmit statt submit: nur so sieht htmx das Absenden und lädt nicht die ganze Seite neu
    if (target.dataset.autosubmit) target.form.requestSubmit();
    // Dateiauswahl in beer.css: der Name erscheint im Textfeld daneben
    if (target.type === 'file') {
      const shown = target.parentElement.querySelector('input[type="text"]');
      if (shown) shown.value = target.files.length ? target.files[0].name : '';
    }
  });

  // In der Capture-Phase: Rückfragen müssen vor dem Submit-Handler von htmx entscheiden
  document.addEventListener('submit', (event) => {
    const form = event.target;
    let cancel = false;
    if (form.dataset.confirm && !window.confirm(form.dataset.confirm)) cancel = true;
    if (!cancel && form.dataset.confirmName) {
      const name = form.dataset.confirmName;
      const what = form.dataset.confirmWhat || 'the table';
      if (window.prompt(`This permanently removes ${what}. Type "${name}" to confirm.`) !== name) cancel = true;
    }
    if (cancel) {
      event.preventDefault();
      event.stopPropagation();
    }
  }, true);

  document.addEventListener('keydown', (event) => {
    if (event.target.id === 'sql-input' && event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
      event.preventDefault();
      event.target.form.requestSubmit();
    }
  });

  // Nach einem Seitenwechsel per htmx: offene Dialoge und die mobile Navigation schließen
  document.addEventListener('htmx:beforeSwap', () => {
    document.querySelectorAll('dialog[open]').forEach((d) => d.close());
    const drawer = byId('nav-drawer');
    if (drawer) drawer.classList.remove('active');
  });
})();
