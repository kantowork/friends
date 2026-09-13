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

// Google Cloud OAuth2 Access Token の取得 (Service Account JWT Bearer Grant)
export async function getGoogleOAuth2AccessToken(
  clientEmail: string,
  privateKeyPem: string,
  scopes: string[] = ["https://www.googleapis.com/auth/datastore"]
): Promise<{ accessToken: string; expiresIn: number }> {
  const now = Math.floor(Date.now() / 1000);
  const header = {
    alg: "RS256",
    typ: "JWT",
  };

  const payload = {
    iss: clientEmail,
    sub: clientEmail,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    scope: scopes.join(" "),
  };

  const assertion = await signJwtRS256(header, payload, privateKeyPem);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Failed to obtain Google OAuth2 access token: ${res.status} ${errText}`);
  }

  const data = (await res.json()) as { access_token: string; expires_in: number };
  return {
    accessToken: data.access_token,
    expiresIn: data.expires_in,
  };
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

export interface VerifiedUser {
  uid: string;
  email?: string;
}

// Firebase ID Token の検証 (Google Identity Toolkit accounts:lookup API)
export async function verifyFirebaseIdToken(
  idToken: string,
  firebaseApiKey: string
): Promise<VerifiedUser> {
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${firebaseApiKey}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ idToken }),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Invalid or expired ID token: ${res.status} ${errText}`);
  }

  const data = (await res.json()) as {
    users?: Array<{ localId: string; email?: string }>;
  };

  if (!data.users || data.users.length === 0 || !data.users[0].localId) {
    throw new Error("No user found for the provided token");
  }

  return {
    uid: data.users[0].localId,
    email: data.users[0].email,
  };
}
