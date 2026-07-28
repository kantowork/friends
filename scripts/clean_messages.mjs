import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { homedir } from "os";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

function resolveProjectId() {
  if (process.env.FIREBASE_PROJECT_ID) return process.env.FIREBASE_PROJECT_ID;
  const root = join(dirname(fileURLToPath(import.meta.url)), "..");
  for (const rcPath of [join(root, ".firebaserc"), join(root, "infra", ".firebaserc")]) {
    try {
      const rc = JSON.parse(readFileSync(rcPath, "utf-8"));
      const id = rc?.projects?.default;
      if (id) return id;
    } catch {
      // ignore
    }
  }
  console.error("❌ Project ID not found.");
  process.exit(1);
}

const projectId = resolveProjectId();

const ADC_PATH = join(homedir(), ".config", "gcloud", "application_default_credentials.json");

if (!existsSync(ADC_PATH)) {
  const firebaseConfigPath = join(homedir(), ".config", "configstore", "firebase-tools.json");
  let refreshToken = null;
  try {
    const firebaseConfig = JSON.parse(readFileSync(firebaseConfigPath, "utf-8"));
    refreshToken = firebaseConfig?.tokens?.refresh_token ?? null;
  } catch {
    // ignore
  }

  if (refreshToken) {
    const adc = {
      client_id: "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com",
      client_secret: "j9iVZfS8ublkFCURxuEeXUaj",
      refresh_token: refreshToken,
      type: "authorized_user",
      universe_domain: "googleapis.com"
    };
    mkdirSync(join(homedir(), ".config", "gcloud"), { recursive: true });
    writeFileSync(ADC_PATH, JSON.stringify(adc, null, 2), { mode: 0o600 });
  } else {
    console.error("❌ Firebase CLI credentials not found.");
    process.exit(1);
  }
}

if (getApps().length === 0) {
  initializeApp({ projectId });
}

const db = getFirestore();

async function cleanMessages() {
  console.log(`🧹 Cleaning messages and chat data in project: ${projectId}...`);
  
  const tenantsSnap = await db.collection("tenants").get();
  
  for (const tenantDoc of tenantsSnap.docs) {
    const tenantId = tenantDoc.id;
    console.log(`Processing tenant: ${tenantId}`);
    
    const chatsSnap = await db.collection("tenants").doc(tenantId).collection("chats").get();
    for (const chatDoc of chatsSnap.docs) {
      const chatId = chatDoc.id;
      console.log(`  Deleting messages in chat: ${chatId}`);
      
      const messagesSnap = await db.collection("tenants").doc(tenantId)
        .collection("chats").doc(chatId)
        .collection("messages").get();
      
      for (const msgDoc of messagesSnap.docs) {
        const msgId = msgDoc.id;
        // Check for reactions subcollection
        const reactionsSnap = await db.collection("tenants").doc(tenantId)
          .collection("chats").doc(chatId)
          .collection("messages").doc(msgId)
          .collection("reactions").get();
        
        for (const reactionDoc of reactionsSnap.docs) {
          await reactionDoc.ref.delete();
        }
        await msgDoc.ref.delete();
      }
      
      // Also delete receipts
      const receiptsSnap = await db.collection("tenants").doc(tenantId)
        .collection("chats").doc(chatId)
        .collection("receipts").get();
      for (const rDoc of receiptsSnap.docs) {
        await rDoc.ref.delete();
      }
      
      // Delete chat document
      await chatDoc.ref.delete();
    }
  }
  
  console.log("✅ All messages, reactions, read receipts, and chats have been cleanly deleted from Firestore.");
}

cleanMessages().catch(err => {
  console.error("❌ Error cleaning messages:", err);
  process.exit(1);
});
