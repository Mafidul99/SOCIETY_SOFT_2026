import { useRef, useState, type FormEvent } from 'react';
import { mutate } from '../api';
import type { Session } from '../types';
import { normalize, text, type Field } from '../utils';
import { Modal, PageHeading, PortalLoader, RecordForm } from '../components/ui';

export function ProfilePage({
  session,
  onSessionUpdated,
  onNotice,
}: {
  session: Session;
  onSessionUpdated: (session: Session) => void;
  onNotice: (message: string) => void;
}) {
  const [form, setForm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [imageBusy, setImageBusy] = useState(false);
  const [imageSaving, setImageSaving] = useState(false);
  const [pendingImage, setPendingImage] = useState<{ data: string; mime: string; preview: string } | null>(null);
  const [removeImage, setRemoveImage] = useState(false);
  const [imageError, setImageError] = useState('');
  const imageInput = useRef<HTMLInputElement>(null);
  const [passwordForm, setPasswordForm] = useState(false);
  const [passwordError, setPasswordError] = useState('');
  const [passwordBusy, setPasswordBusy] = useState(false);
  const [passwords, setPasswords] = useState({ currentPassword: '', newPassword: '' });
  const userFields: Field[] = [
    { name: 'name', label: 'Full name', required: true },
    { name: 'email', label: 'Email address', type: 'email', required: true },
    { name: 'phoneNumber', label: 'Phone number', type: 'tel' },
  ];
  const saveProfile = async (values: Record<string, string | boolean>) => {
    setBusy(true);
    try {
      const payload: Record<string, unknown> = {
        name: values.name, email: values.email, phoneNumber: values.phoneNumber,
      };
      await mutate('updateMyProfile', session, payload);
      onSessionUpdated({ ...session, user: { ...session.user, name: text(values.name), email: text(values.email), phoneNumber: text(values.phoneNumber) } });
      setForm(false); onNotice('Profile updated.');
    } finally { setBusy(false); }
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
    } finally { setImageBusy(false); }
  };
  const saveProfileImage = async () => {
    if (!pendingImage && !removeImage) return;
    setImageSaving(true);
    setImageError('');
    try {
      await mutate('updateMyProfile', session, {
        name: session.user.name,
        email: session.user.email,
        phoneNumber: session.user.phoneNumber,
        profileImageChanged: true,
        ...(pendingImage ? { profileImageData: pendingImage.data, profileImageMimeType: pendingImage.mime } : {}),
      });
      onSessionUpdated({
        ...session,
        user: { ...session.user, profileImageUrl: pendingImage?.preview || '' },
      });
      setPendingImage(null);
      setRemoveImage(false);
      onNotice(pendingImage ? 'Profile photo updated.' : 'Profile photo removed.');
    } catch (cause) {
      setImageError(cause instanceof Error ? cause.message : 'Could not update the profile photo.');
    } finally { setImageSaving(false); }
  };
  const cancelImageChange = () => {
    setPendingImage(null);
    setRemoveImage(false);
    setImageError('');
    if (imageInput.current) imageInput.current.value = '';
  };
  const changePassword = async (event: FormEvent) => {
    event.preventDefault(); setPasswordError(''); setPasswordBusy(true);
    try {
      await mutate('changePassword', session, passwords);
      setPasswordForm(false); setPasswords({ currentPassword: '', newPassword: '' }); onNotice('Password changed successfully.');
    } catch (cause) { setPasswordError(cause instanceof Error ? cause.message : 'Could not change the password.'); }
    finally { setPasswordBusy(false); }
  };
  const picture = pendingImage?.preview || (removeImage ? '' : session.user.profileImageUrl);
  const hasImageChange = Boolean(pendingImage || removeImage);
  return <>
    <PageHeading title="My profile" subtitle="Manage your account details and sign-in security." />
    <div className="profile-grid">
      <section className="panel profile-card">
        <div className="profile-banner">
          <div className="profile-photo-wrap">
            <div className="profile-avatar">{picture ? <img src={picture} alt={`${session.user.name} profile`} /> : session.user.name.slice(0, 1).toUpperCase()}</div>
            <button type="button" className="profile-photo-edit" aria-label="Choose a new profile photo" title="Choose a new profile photo" disabled={imageBusy || imageSaving} onClick={() => imageInput.current?.click()}>
              <svg aria-hidden="true" viewBox="0 0 24 24"><path d="M4 7.5h3l1.5-2h7l1.5 2h3v11H4z" /><circle cx="12" cy="13" r="3.5" /></svg>
            </button>
            <input ref={imageInput} className="profile-photo-input" type="file" accept="image/jpeg,image/png,image/webp" aria-label="Choose a profile photo" disabled={imageBusy || imageSaving} onChange={(event) => {
              void chooseImage(event.target.files?.[0]);
              event.currentTarget.value = '';
            }} />
          </div>
          <div className="profile-banner-copy"><p className="eyebrow">ACCOUNT PROFILE</p><h2>{session.user.name}</h2><span className={`role-pill role-${normalize(session.user.role)}`}>{session.user.role}</span>
            <div className="profile-photo-actions">
              <button type="button" className="profile-photo-link" disabled={imageBusy || imageSaving} onClick={() => imageInput.current?.click()}>{imageBusy ? <><PortalLoader label="Preparing photo" inline size={14} /> Preparing photo…</> : 'Change photo'}</button>
              {session.user.profileImageUrl && !removeImage && <button type="button" className="profile-photo-link profile-photo-remove" disabled={imageBusy || imageSaving} onClick={() => { setPendingImage(null); setRemoveImage(true); setImageError(''); }}>Remove</button>}
            </div>
            <p className="profile-photo-hint">JPG, PNG, or WebP · large photos are resized automatically</p>
          </div>
        </div>
        {imageError && <div className="profile-photo-message profile-photo-error" role="alert">{imageError}</div>}
        {hasImageChange && <div className="profile-photo-confirm">
          <span>{removeImage ? 'Remove your current profile photo?' : 'Preview your new photo, then save to update your account.'}</span>
          <div><button type="button" className="button button-quiet" disabled={imageSaving} onClick={cancelImageChange}>Cancel</button><button type="button" className="button button-primary" disabled={imageSaving} onClick={() => void saveProfileImage()}>{imageSaving && <PortalLoader label={removeImage ? 'Removing photo' : 'Saving photo'} inline size={16} />}{imageSaving ? (removeImage ? 'Removing…' : 'Saving…') : removeImage ? 'Remove photo' : 'Save photo'}</button></div>
        </div>}
        <dl className="profile-details">
          <div><dt>Email</dt><dd>{session.user.email}</dd></div><div><dt>Phone</dt><dd>{session.user.phoneNumber || 'Not provided'}</dd></div>
          <div><dt>Account number</dt><dd>{session.user.accountNo || 'Not assigned'}</dd></div><div><dt>Account role</dt><dd>{session.user.role}</dd></div>
        </dl>
        <div className="profile-actions"><button className="button button-primary" onClick={() => setForm(true)}>Edit profile</button><button className="button button-secondary" onClick={() => setPasswordForm(true)}>Change password</button></div>
      </section>
      <aside className="notice-card"><strong>Account security</strong><span>Never share your password or one-time payment information. Contact your administrator if you suspect unauthorized access.</span></aside>
    </div>
    {form && <RecordForm title="Edit profile" fields={userFields} initial={session.user} busy={busy} onClose={() => setForm(false)} onSubmit={saveProfile} />}
    {passwordForm && <Modal title="Change password" onClose={() => setPasswordForm(false)}><form className="record-form" onSubmit={(event) => void changePassword(event)}>
      <label className="field"><span>Current password</span><input required type="password" autoComplete="current-password" value={passwords.currentPassword} onChange={(event) => setPasswords({ ...passwords, currentPassword: event.target.value })} /></label>
      <label className="field"><span>New password (8+ characters)</span><input required minLength={8} type="password" autoComplete="new-password" value={passwords.newPassword} onChange={(event) => setPasswords({ ...passwords, newPassword: event.target.value })} /></label>
      {passwordError && <p className="form-error" role="alert">{passwordError}</p>}
      <footer className="modal-actions"><button type="button" className="button button-quiet" onClick={() => setPasswordForm(false)}>Cancel</button><button className="button button-primary" disabled={passwordBusy}>{passwordBusy && <PortalLoader label="Updating password" inline size={16} />}{passwordBusy ? 'Updating…' : 'Update password'}</button></footer>
    </form></Modal>}
  </>;
}

const MAX_PROFILE_IMAGE_BYTES = 300 * 1024;
const MAX_PROFILE_IMAGE_DIMENSION = 512;

async function prepareProfileImage(file: File) {
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file);
  } catch {
    throw new Error('The selected file is not a readable image.');
  }

  try {
    if (file.size <= MAX_PROFILE_IMAGE_BYTES) {
      const dataUrl = await readAsDataUrl(file);
      return { data: dataUrl.slice(dataUrl.indexOf(',') + 1), mime: file.type, preview: dataUrl };
    }

    const scale = Math.min(1, MAX_PROFILE_IMAGE_DIMENSION / Math.max(bitmap.width, bitmap.height));
    let width = Math.max(1, Math.round(bitmap.width * scale));
    let height = Math.max(1, Math.round(bitmap.height * scale));
    const canvas = document.createElement('canvas');
    const context = canvas.getContext('2d');
    if (!context) throw new Error('This browser cannot prepare the selected image.');
    for (let attempt = 0; attempt < 6; attempt += 1) {
      canvas.width = width;
      canvas.height = height;
      context.fillStyle = '#fff';
      context.fillRect(0, 0, width, height);
      context.drawImage(bitmap, 0, 0, width, height);
      const blob = await canvasToJpeg(canvas, Math.max(0.48, 0.84 - attempt * 0.08));
      if (blob.size <= MAX_PROFILE_IMAGE_BYTES) {
        const preview = await readAsDataUrl(blob);
        return { data: preview.slice(preview.indexOf(',') + 1), mime: 'image/jpeg', preview };
      }
      width = Math.max(96, Math.round(width * 0.78));
      height = Math.max(96, Math.round(height * 0.78));
    }
    throw new Error('Could not reduce this image below 300 KB. Choose a smaller image.');
  } finally {
    bitmap.close();
  }
}

function readAsDataUrl(blob: Blob) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => typeof reader.result === 'string' ? resolve(reader.result) : reject(new Error('Could not read the selected image.'));
    reader.onerror = () => reject(new Error('Could not read the selected image.'));
    reader.readAsDataURL(blob);
  });
}

function canvasToJpeg(canvas: HTMLCanvasElement, quality: number) {
  return new Promise<Blob>((resolve, reject) => {
    canvas.toBlob((blob) => blob ? resolve(blob) : reject(new Error('Could not prepare the selected image.')), 'image/jpeg', quality);
  });
}
