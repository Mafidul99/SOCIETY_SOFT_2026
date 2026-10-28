import { useCallback, useEffect, useRef, useState } from 'react';
import { getRows, mutate } from '../api';
import type { RecordRow, Session } from '../types';
import { allows, normalize, text, type Field } from '../utils';
import { PageHeading, RecordForm, RowActions, StatePanel, Table } from '../components/ui';
import { prepareProfileImage, type PreparedProfileImage } from '../profileImage';

function UserAvatar({ name, imageUrl }: { name: string; imageUrl: string }) {
  const [imageFailed, setImageFailed] = useState(false);
  useEffect(() => setImageFailed(false), [imageUrl]);
  const initial = name.trim().slice(0, 1).toUpperCase() || '?';

  return (
    <span className="avatar users-avatar">
      {imageUrl && !imageFailed
        ? <img src={imageUrl} alt="" loading="lazy" decoding="async" onError={() => setImageFailed(true)} />
        : initial}
    </span>
  );
}

export function UsersPage({ session, onNotice }: { session: Session; onNotice: (message: string) => void }) {
  const [rows, setRows] = useState<RecordRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [query, setQuery] = useState('');
  const [formRow, setFormRow] = useState<RecordRow | null | undefined>(undefined);
  const [busy, setBusy] = useState(false);
  const [imageBusy, setImageBusy] = useState(false);
  const [pendingImage, setPendingImage] = useState<PreparedProfileImage | null>(null);
  const [removeImage, setRemoveImage] = useState(false);
  const [imageError, setImageError] = useState('');
  const imageInput = useRef<HTMLInputElement>(null);
  const canAdd = allows(session, 'user_add');
  const canEdit = allows(session, 'user_edit');
  const canDelete = allows(session, 'user_delete');
  const load = useCallback(async () => {
    setLoading(true); setError('');
    try { setRows(await getRows('getUsers', session)); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not load users.'); }
    finally { setLoading(false); }
  }, [session]);
  useEffect(() => { void load(); }, [load]);

  const openEditor = (row: RecordRow | null) => {
    setPendingImage(null);
    setRemoveImage(false);
    setImageError('');
    if (imageInput.current) imageInput.current.value = '';
    setFormRow(row);
  };
  const closeEditor = () => {
    setFormRow(undefined);
    setPendingImage(null);
    setRemoveImage(false);
    setImageError('');
  };
  const chooseImage = async (file?: File) => {
    if (!file) return;
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
      setImageError('Choose a JPG, PNG, or WebP image.');
      return;
    }
    setImageBusy(true);
    setImageError('');
    try {
      setPendingImage(await prepareProfileImage(file));
      setRemoveImage(false);
    } catch (cause) {
      setImageError(cause instanceof Error ? cause.message : 'Could not prepare the selected image.');
    } finally {
      setImageBusy(false);
    }
  };
  const save = async (values: Record<string, string | boolean>) => {
    setBusy(true);
    try {
      const editing = Boolean(formRow);
      const role = session.user.role === 'Admin' ? text(values.role) : text(formRow?.role || 'Member');
      const payload = {
        ...(editing ? { userId: formRow?.id } : {}),
        name: values.name, email: values.email, phoneNumber: values.phoneNumber,
        role, ...(values.password ? { password: values.password } : {}),
        ...(role === 'Member' && session.user.role === 'Admin' ? {
          dailyAccess: values.dailyAccess, weeklyAccess: values.weeklyAccess, monthlyAccess: values.monthlyAccess,
        } : {}),
        ...(editing && (pendingImage || removeImage) ? {
          profileImageChanged: true,
          ...(pendingImage ? { profileImageData: pendingImage.data, profileImageMimeType: pendingImage.mime } : {}),
        } : {}),
      };
      await mutate(editing ? 'editUser' : 'addUser', session, payload);
      closeEditor();
      const notice = pendingImage
        ? 'User account and member photo updated.'
        : removeImage
          ? 'User account updated and member photo removed.'
          : editing ? 'User account updated.' : 'User account created.';
      onNotice(notice);
      await load();
    } finally { setBusy(false); }
  };
  const remove = async (row: RecordRow) => {
    if (row.id === session.user.id) { onNotice('You cannot deactivate your own account.'); return; }
    if (!window.confirm(`Deactivate ${text(row.name)}?`)) return;
    try { await mutate('deleteUser', session, { userId: row.id }); onNotice('User account deactivated.'); await load(); }
    catch (cause) { onNotice(cause instanceof Error ? cause.message : 'Could not deactivate this user.'); }
  };
  const visible = rows.filter((row) => [row.name, row.email, row.accountNo, row.role].some((value) => normalize(value).includes(normalize(query))));
  const columns = [
    { key: 'name', label: 'Name', render: (row: RecordRow) => {
      const name = text(row.name);
      return <div className="person-cell"><UserAvatar name={name} imageUrl={text(row.profileImageUrl)} /><span className="users-person-copy"><strong>{name || 'Unnamed user'}</strong><small>{text(row.accountNo) || 'No account number'}</small></span></div>;
    } },
    { key: 'email', label: 'Email' }, { key: 'phoneNumber', label: 'Phone' },
    { key: 'role', label: 'Role', render: (row: RecordRow) => <span className={`role-pill role-${normalize(row.role)}`}>{text(row.role)}</span> },
    { key: 'actions', label: 'Actions', render: (row: RecordRow) => <RowActions edit={canEdit ? () => openEditor(row) : undefined} remove={canDelete ? () => void remove(row) : undefined} /> },
  ];
  const fields: Field[] = [
    { name: 'name', label: 'Full name', required: true },
    { name: 'email', label: 'Email address', type: 'email', required: true },
    { name: 'phoneNumber', label: 'Phone number', type: 'tel' },
    ...(session.user.role === 'Admin' ? [{ name: 'role', label: 'Role', type: 'select' as const, required: true, options: ['Admin', 'Collector', 'Member'].map((value) => ({ value, label: value })) }] : []),
    { name: 'password', label: formRow ? 'New password (leave blank to keep current)' : 'Initial password', type: 'password', required: !formRow },
    ...(session.user.role === 'Admin' ? [
      { name: 'dailyAccess', label: 'Allow Daily reports', type: 'checkbox' as const },
      { name: 'weeklyAccess', label: 'Allow Weekly reports', type: 'checkbox' as const },
      { name: 'monthlyAccess', label: 'Allow Monthly reports', type: 'checkbox' as const },
    ] : []),
  ];
  return <>
    <PageHeading title="Users" subtitle="Manage portal accounts, roles, and member access."
      action={canAdd && <button className="button button-primary" onClick={() => openEditor(null)}>＋ Add user</button>} />
    <section className="panel users-panel">
      <div className="panel-toolbar">
        <label className="search-field"><span>⌕</span><input placeholder="Search name, account, email, or role" value={query} onChange={(event) => setQuery(event.target.value)} /></label>
        <span className="badge">{visible.length} active accounts</span>
      </div>
      <StatePanel loading={loading} error={error} retry={() => void load()}><Table rows={visible} columns={columns} /></StatePanel>
    </section>
    {formRow !== undefined && <RecordForm key={formRow ? text(formRow.id) : 'new-user'} title={formRow ? 'Edit user account' : 'Create user account'} fields={fields}
      initial={formRow ?? { role: 'Member', dailyAccess: true, weeklyAccess: true, monthlyAccess: true }}
      busy={busy || imageBusy} onClose={closeEditor} onSubmit={save}
      extraContent={formRow && normalize(formRow.role) === 'member' && session.user.role === 'Admin' && <section className="user-image-editor" aria-label="Member profile photo">
        <div className="user-image-preview">
          {pendingImage?.preview || (!removeImage && text(formRow.profileImageUrl))
            ? <img src={pendingImage?.preview || text(formRow.profileImageUrl)} alt={`${text(formRow.name)} profile`} />
            : text(formRow.name).trim().slice(0, 1).toUpperCase() || '?'}
        </div>
        <div className="user-image-copy">
          <strong>Member profile photo</strong>
          <span>JPG, PNG, or WebP. Large photos are resized automatically.</span>
          <div className="user-image-actions">
            <input ref={imageInput} className="profile-photo-input" type="file" accept="image/jpeg,image/png,image/webp" aria-label="Choose a member profile photo" disabled={imageBusy || busy} onChange={(event) => {
              void chooseImage(event.currentTarget.files?.[0]);
              event.currentTarget.value = '';
            }} />
            <button type="button" className="button button-secondary" disabled={imageBusy || busy} onClick={() => imageInput.current?.click()}>
              {imageBusy ? 'Preparing photo…' : pendingImage ? 'Choose another photo' : 'Change photo'}
            </button>
            {pendingImage && <button type="button" className="button button-quiet" disabled={busy} onClick={() => { setPendingImage(null); setImageError(''); }}>Cancel photo</button>}
            {!pendingImage && Boolean(formRow.profileImageUrl) && !removeImage && <button type="button" className="button button-quiet danger-text" disabled={busy} onClick={() => { setRemoveImage(true); setImageError(''); }}>Remove photo</button>}
            {removeImage && <button type="button" className="button button-quiet" disabled={busy} onClick={() => setRemoveImage(false)}>Keep current photo</button>}
          </div>
          {imageError && <span className="user-image-error" role="alert">{imageError}</span>}
        </div>
      </section>}
    />}
  </>;
}
