// Web Crypto API (crypto.subtle) による RS256 JWT 署名ライブラリ
// Firebase Custom Token 生成および Google OAuth2 トークン署名に対応

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function stringToBase64Url(str: string): string {
  const bytes = new TextEncoder().encode(str);
  return base64UrlEncode(bytes);
}

// PEM 形式の PKCS#8 秘密鍵を CryptoKey に変換
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const cleanPem = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");

  const binaryString = atob(cleanPem);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }

  return await crypto.subtle.importKey(
    "pkcs8",
    bytes.buffer,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"]
  );
}

// 汎用 RS256 JWT 署名
export async function signJwtRS256(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
  privateKeyPem: string
): Promise<string> {
  const privateKey = await importPrivateKey(privateKeyPem);
  const headerB64 = stringToBase64Url(JSON.stringify(header));
  const payloadB64 = stringToBase64Url(JSON.stringify(payload));
  const dataToSign = `${headerB64}.${payloadB64}`;

  const signatureBuffer = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
    new TextEncoder().encode(dataToSign)
  );

  const signatureB64 = base64UrlEncode(new Uint8Array(signatureBuffer));
  return `${dataToSign}.${signatureB64}`;
}

// Firebase Auth Custom Token の生成
export async function createFirebaseCustomToken(
  clientEmail: string,
  privateKeyPem: string,
  uid: string
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = {
    alg: "RS256",
    typ: "JWT",
  };

  const payload = {
    iss: clientEmail,
    sub: clientEmail,
    aud: "https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit",
    iat: now,
    exp: now + 3600, // 1時間有効
    uid: uid,
  };

  return await signJwtRS256(header, payload, privateKeyPem);
}

// Firebase Custom Token を Firebase ID Token に交換 (Firestore REST API 認可用)
export async function exchangeCustomTokenToIdToken(
  customToken: string,
  firebaseApiKey: string
): Promise<string> {
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${firebaseApiKey}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      token: customToken,
      returnSecureToken: true,
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Failed to exchange custom token for id token: ${res.status} ${errText}`);
  }

  const data = (await res.json()) as { idToken: string };
  return data.idToken;
}
