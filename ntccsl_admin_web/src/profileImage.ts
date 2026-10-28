const MAX_PROFILE_IMAGE_BYTES = 300 * 1024;
const MAX_PROFILE_IMAGE_DIMENSION = 512;

export type PreparedProfileImage = {
  data: string;
  mime: string;
  preview: string;
};

export async function prepareProfileImage(file: File): Promise<PreparedProfileImage> {
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
