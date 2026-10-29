// Account deletion for BOOMFORGE (Google Play's web deletion requirement).
// Google-linked players delete their own account here; guests send a
// request that is stored in Firestore `deletionRequests` for the developer.
import { initializeApp } from 'https://www.gstatic.com/firebasejs/11.0.2/firebase-app.js';
import {
  getAuth, GoogleAuthProvider, onAuthStateChanged, signInWithPopup,
  signInWithRedirect, getRedirectResult, signOut, deleteUser,
} from 'https://www.gstatic.com/firebasejs/11.0.2/firebase-auth.js';
import {
  getFirestore, doc, deleteDoc, addDoc, collection, serverTimestamp,
} from 'https://www.gstatic.com/firebasejs/11.0.2/firebase-firestore.js';

// Web app config (public by design; access is enforced by firestore.rules).
const app = initializeApp({
  apiKey: 'AIzaSyAxprvvqMzbEJw-XktZkrOaxPEOfpyYzyc',
  authDomain: 'ball-blast-d0a65.firebaseapp.com',
  projectId: 'ball-blast-d0a65',
  appId: '1:182359966028:web:e4fd72c27f5fca7b92cfe9',
});
const auth = getAuth(app);
const db = getFirestore(app);

const $ = (id) => document.getElementById(id);
const say = (el, text, ok) => {
  el.textContent = text;
  el.className = 'status ' + (ok === undefined ? '' : ok ? 'ok' : 'err');
};
const gStatus = $('google-status');

onAuthStateChanged(auth, (user) => {
  const linked = user && !user.isAnonymous;
  $('signed-out').classList.toggle('hidden', !!linked);
  $('signed-in').classList.toggle('hidden', !linked);
  $('who').textContent = linked ? (user.email || user.uid) : '';
});

getRedirectResult(auth).catch((e) => say(gStatus, message(e), false));

function message(e) {
  switch (e && e.code) {
    case 'auth/popup-closed-by-user':
    case 'auth/cancelled-popup-request':
      return 'Sign-in cancelled.';
    case 'auth/network-request-failed':
      return 'No internet connection. Try again.';
    case 'auth/requires-recent-login':
      return 'For your security, sign out, sign in again and retry.';
    case 'permission-denied':
      return 'Permission denied. Sign out, sign in again and retry.';
    default:
      return 'Something went wrong (' + ((e && e.code) || e) + '). Try again.';
  }
}

$('sign-in').addEventListener('click', async () => {
  say(gStatus, '');
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ prompt: 'select_account' });
  try {
    await signInWithPopup(auth, provider);
  } catch (e) {
    if (e.code === 'auth/popup-blocked') return signInWithRedirect(auth, provider);
    say(gStatus, message(e), false);
  }
});

$('sign-out').addEventListener('click', () => signOut(auth));

$('delete').addEventListener('click', async () => {
  const user = auth.currentUser;
  if (!user) return;
  if (!confirm('Delete your BOOMFORGE account (' + (user.email || user.uid) +
      ') and all cloud progress? This cannot be undone.')) return;
  $('delete').disabled = true;
  say(gStatus, 'Deleting…');
  try {
    await deleteDoc(doc(db, 'players', user.uid));
    await deleteUser(user);
    say(gStatus, 'Done. Your BOOMFORGE account and cloud save were deleted. ' +
      'To remove the copy on your phone, uninstall the game.', true);
  } catch (e) {
    say(gStatus, message(e), false);
  } finally {
    $('delete').disabled = false;
  }
});

$('request-form').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const status = $('request-status');
  const playerId = $('player-id').value.trim();
  const contact = $('contact').value.trim();
  const note = $('note').value.trim();
  if (!playerId && !note) {
    return say(status, 'Enter your Player ID or describe your request.', false);
  }
  $('send').disabled = true;
  say(status, 'Sending…');
  try {
    await addDoc(collection(db, 'deletionRequests'), {
      playerId, contact, note, createdAt: serverTimestamp(),
    });
    $('request-form').reset();
    say(status, 'Request received. We will complete it within 30 days.', true);
  } catch (e) {
    say(status, message(e), false);
  } finally {
    $('send').disabled = false;
  }
});
