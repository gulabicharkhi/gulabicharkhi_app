// ============================================================
// config/emailService.js — UPDATED
// Render (free tier) blocks SMTP ports (25/465/587), so
// the Brevo HTTP API (port 443) is now used. SMTP is only a local fallback.
// ============================================================
const nodemailer = require('nodemailer');

const getConfig = () => ({
  apiKey: (process.env.BREVO_API_KEY || '').trim(),
  // VERIFIED sender email in Brevo (Senders & IP -> Senders). Do not put the smtp-brevo.com login here
  from: (process.env.EMAIL_FROM || '').trim(),
  fromName: (process.env.EMAIL_FROM_NAME || 'Gulabi Charkhi').trim(),
  host: (process.env.EMAIL_HOST || 'smtp-relay.brevo.com').trim(),
  port: parseInt(process.env.EMAIL_PORT || '587', 10),
  user: (process.env.EMAIL_USER || '').trim(),
  pass: (process.env.EMAIL_PASS || '').trim(),
});

const useApi = () => !!getConfig().apiKey;

const isConfigured = () => {
  const c = getConfig();
  if (c.apiKey) return !!c.from;
  if (!c.user || !c.pass) return false;
  if (c.user.includes('aapkaemail') || c.pass.toLowerCase().startsWith('xxxx')) return false;
  return true;
};

const createTransporter = () => {
  const { host, port, user, pass } = getConfig();
  return nodemailer.createTransport({
    host,
    port,
    secure: process.env.EMAIL_SECURE === 'true',
    auth: { user, pass },
    connectionTimeout: 15000,
    greetingTimeout: 15000,
    socketTimeout: 20000,
  });
};

const explainError = (error) => {
  const code = error && error.code;
  const msg = (error && error.message) || '';
  if (error && error.brevoStatus) {
    if (error.brevoStatus === 401) return 'Brevo API key is invalid (an xkeysib-... API key is required, not an SMTP key).';
    if (error.brevoStatus === 403) return `Brevo returned forbidden: ${msg}. Check that the API key has the Transactional email = All permission.`;
    if (error.brevoStatus === 400) return `Brevo rejected the request: ${msg}. EMAIL_FROM must be a verified sender.`;
    return `Brevo API error ${error.brevoStatus}: ${msg}`;
  }
  if (code === 'EAUTH' || /Invalid login|Username and Password not accepted|535/i.test(msg)) {
    return 'Brevo rejected the login — the SMTP key is wrong or SMTP is not enabled on the account.';
  }
  if (['ETIMEDOUT', 'ESOCKET', 'ECONNECTION', 'ECONNREFUSED', 'EDNS', 'ENOTFOUND'].includes(code)) {
    return `Server ${getConfig().host}:${getConfig().port} is unreachable (Render blocks SMTP — use BREVO_API_KEY).`;
  }
  if (code === 'EENVELOPE') return 'Receiver email address is not valid.';
  return msg || 'Unknown email error';
};

const escapeHtml = (s = '') =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// ---------- Brevo HTTP API (port 443) ----------
const sendViaApi = async ({ to, subject, text, html }) => {
  const { apiKey, from, fromName } = getConfig();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 20000);
  try {
    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': apiKey, 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({
        sender: { name: fromName, email: from },
        to: [{ email: to }],
        subject,
        textContent: text,
        htmlContent: html,
      }),
      signal: controller.signal,
    });
    if (!res.ok) {
      let detail = '';
      try { detail = (await res.json()).message || ''; } catch (_) {}
      const err = new Error(detail || res.statusText);
      err.brevoStatus = res.status;
      throw err;
    }
  } finally {
    clearTimeout(timer);
  }
};

const verifyEmailSetup = async () => {
  if (!isConfigured()) {
    console.warn('⚠️  Email config missing (BREVO_API_KEY + EMAIL_FROM, or EMAIL_USER/EMAIL_PASS). OTP will only be shown in the console.');
    return false;
  }
  try {
    if (useApi()) {
      // A restricted key (Transactional email only) returns 403 on the /account endpoint,
      // so we skip the network check here. The real check happens on the first OTP mail.
      console.log(`✅ Email ready — Brevo HTTP API, sender ${getConfig().from}`);
    } else {
      await createTransporter().verify();
      const { host, port, user } = getConfig();
      console.log(`✅ Email ready — ${user} via ${host}:${port}`);
    }
    return true;
  } catch (error) {
    console.error('❌ Email setup FAIL:', explainError(error));
    return false;
  }
};

const sendOtpEmail = async (toEmail, otp, userName, purpose = 'verify') => {
  const isReset = purpose === 'reset';
  const codeName = isReset ? 'password reset code' : 'verification code';

  if (!isConfigured()) {
    const hint = 'Email config is not set (BREVO_API_KEY + EMAIL_FROM).';
    console.error('Email send error:', hint);
    return { success: false, error: hint, hint };
  }

  const subject = `${otp} is your Gulabi Charkhi ${codeName}`;
  const text = `Hello ${userName || 'Player'}, your Gulabi Charkhi ${codeName} is ${otp}. It expires in 10 minutes. Never share this code with anyone.`;
  const html = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
            body { font-family: Arial, sans-serif; background: #FFF0F5; margin: 0; padding: 20px; }
            .container { max-width: 480px; margin: 0 auto; background: white; border-radius: 20px; overflow: hidden; box-shadow: 0 4px 20px rgba(233,30,140,0.1); }
            .header { background: linear-gradient(135deg, #E91E8C, #7B2FBE); padding: 32px 24px; text-align: center; }
            .header h1 { color: white; margin: 0; font-size: 24px; }
            .header p { color: rgba(255,255,255,0.8); margin: 4px 0 0; font-size: 13px; }
            .body { padding: 32px 24px; text-align: center; }
            .greeting { font-size: 16px; color: #333; margin-bottom: 8px; }
            .otp-label { color: #9E9E9E; font-size: 13px; margin-bottom: 16px; }
            .otp-box { display: inline-block; background: #FFF0F5; border: 2px dashed #E91E8C; border-radius: 16px; padding: 20px 40px; margin: 8px 0 20px; }
            .otp-code { font-size: 42px; font-weight: 900; color: #E91E8C; letter-spacing: 10px; }
            .expiry { color: #9E9E9E; font-size: 13px; margin: 8px 0 24px; }
            .warning { background: #FFF8E1; border-radius: 10px; padding: 12px 16px; font-size: 12px; color: #795548; }
            .footer { background: #F8F8F8; padding: 16px 24px; text-align: center; font-size: 11px; color: #BDBDBD; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h1>Gulabi Charkhi</h1>
              <p>Pink Spool • Kite Battle Arena</p>
            </div>
            <div class="body">
              <p class="greeting">Hello, <strong>${escapeHtml(userName || 'Player')}</strong>!</p>
              <p class="otp-label">Here is your ${codeName}:</p>
              <div class="otp-box">
                <div class="otp-code">${escapeHtml(otp)}</div>
              </div>
              <p class="expiry">This code expires in <strong>10 minutes</strong></p>
              <div class="warning">
                Never share this code with anyone.<br>
                Gulabi Charkhi team will never ask for your OTP.
              </div>
            </div>
            <div class="footer">
              © ${new Date().getFullYear()} Gulabi Charkhi • Jaipur, Rajasthan
            </div>
          </div>
        </body>
        </html>
      `;

  try {
    if (useApi()) {
      await sendViaApi({ to: toEmail, subject, text, html });
    } else {
      const { user, from } = getConfig();
      await createTransporter().sendMail({
        from: `"Gulabi Charkhi" <${from || user}>`,
        to: toEmail,
        subject,
        text,
        html,
      });
    }
    return { success: true };
  } catch (error) {
    const hint = explainError(error);
    console.error('Email send error:', hint, `[${error.code || error.brevoStatus || 'no-code'}] ${error.message}`);
    return { success: false, error: error.message, hint };
  }
};

module.exports = { sendOtpEmail, verifyEmailSetup, isConfigured };
