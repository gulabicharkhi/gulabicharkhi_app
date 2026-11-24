const nodemailer = require('nodemailer');

const getConfig = () => ({
  host: (process.env.EMAIL_HOST || 'smtp-relay.brevo.com').trim(),
  port: parseInt(process.env.EMAIL_PORT || '587', 10),
  user: (process.env.EMAIL_USER || '').trim(),
  pass: (process.env.EMAIL_PASS || '').trim(),
});

const isConfigured = () => {
  const { user, pass } = getConfig();
  if (!user || !pass) return false;
  if (user.includes('aapkaemail') || pass.toLowerCase().startsWith('xxxx')) return false;
  return true;
};

const createTransporter = () => {
  const { host, port, user, pass } = getConfig();
  return nodemailer.createTransport({
    host,
    port,
    secure: false,
    auth: { user, pass },
    connectionTimeout: 15000,
    greetingTimeout: 15000,
    socketTimeout: 20000,
  });
};

const explainError = (error) => {
  const code = error && error.code;
  const msg = (error && error.message) || '';
  if (code === 'EAUTH' || /Invalid login|Username and Password not accepted|535/i.test(msg)) {
    return 'Brevo ne login reject kiya — SMTP key galat hai ya account mein SMTP enable nahi hai.';
  }
  if (['ETIMEDOUT', 'ESOCKET', 'ECONNECTION', 'ECONNREFUSED', 'EDNS', 'ENOTFOUND'].includes(code)) {
    return `Server ${getConfig().host}:${getConfig().port} tak pahunch nahi pa raha.`;
  }
  if (code === 'EENVELOPE') return 'Receiver email address valid nahi hai.';
  return msg || 'Unknown email error';
};

const escapeHtml = (s = '') =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const verifyEmailSetup = async () => {
  if (!isConfigured()) {
    console.warn('⚠️  EMAIL_USER / EMAIL_PASS .env mein set nahi hain. OTP sirf console mein dikhega.');
    return false;
  }
  try {
    await createTransporter().verify();
    const { host, port, user } = getConfig();
    console.log(`✅ Email ready — ${user} via ${host}:${port}`);
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
    const hint = '.env mein EMAIL_USER / EMAIL_PASS set nahi hain.';
    console.error('Email send error:', hint);
    return { success: false, error: hint, hint };
  }

  try {
    const transporter = createTransporter();
    const { user } = getConfig();

    await transporter.sendMail({
      from: `"Gulabi Charkhi" <${user}>`,
      to: toEmail,
      subject: `${otp} is your Gulabi Charkhi ${codeName}`,
      text: `Hello ${userName || 'Player'}, your Gulabi Charkhi ${codeName} is ${otp}. It expires in 10 minutes. Never share this code with anyone.`,
      html: `
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
              <p>गुलाबी चरखी • Kite Battle Arena</p>
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
      `,
    });

    return { success: true };
  } catch (error) {
    const hint = explainError(error);
    console.error('Email send error:', hint, `[${error.code || 'no-code'}] ${error.message}`);
    return { success: false, error: error.message, hint };
  }
};

module.exports = { sendOtpEmail, verifyEmailSetup, isConfigured };