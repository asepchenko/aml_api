import { getPool } from '../db.js';

const EXPO_PUSH_URL = 'https://exp.host/--/api/v2/push/send';

/**
 * Get active device tokens for a user
 * @param {string|number} userId 
 * @returns {Promise<string[]>}
 */
async function getDeviceTokensForUser(userId) {
  try {
    const pool = getPool();
    const [rows] = await pool.query(
      'SELECT token FROM device_tokens WHERE user_id = ? AND is_active = TRUE',
      [userId]
    );
    return rows.map(r => r.token);
  } catch (error) {
    console.error('[PUSH] Error getting device tokens:', error);
    return [];
  }
}

/**
 * Mark a token as inactive
 * @param {string} token 
 */
async function deactivateToken(token) {
  try {
    const pool = getPool();
    await pool.query(
      'UPDATE device_tokens SET is_active = FALSE WHERE token = ?',
      [token]
    );
    console.log(`[PUSH] Token deactivated: ${token}`);
  } catch (error) {
    console.error('[PUSH] Error deactivating token:', error);
  }
}

/**
 * Send push notification via Expo
 * @param {string|number} userId 
 * @param {string} title 
 * @param {string} body 
 * @param {object} data 
 */
export async function sendPushNotification(userId, title, body, data = {}) {
  try {
    const tokens = await getDeviceTokensForUser(userId);
    
    if (tokens.length === 0) {
      console.log(`[PUSH] No active tokens for user ${userId}`);
      return;
    }

    const messages = tokens.map(token => ({
      to: token,
      title,
      body,
      sound: 'default',
      badge: 1,
      data: {
        ...data,
        timestamp: new Date().toISOString(),
      },
      priority: 'high',
    }));

    const response = await fetch(EXPO_PUSH_URL, {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Accept-Encoding': 'gzip, deflate',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(messages),
    });

    const result = await response.json();

    if (result.data) {
      result.data.forEach((item, index) => {
        if (item.status === 'error' && item.message === 'DeviceNotRegistered') {
          deactivateToken(tokens[index]);
        }
      });
    }

    console.log(`[PUSH] Notification sent to user ${userId}:`, result);
    return result;
  } catch (error) {
    console.error('[PUSH] Error sending notification:', error);
  }
}

/**
 * Send notification to multiple users
 * @param {Array<string|number>} userIds 
 * @param {string} title 
 * @param {string} body 
 * @param {object} data 
 */
export async function sendPushToUsers(userIds, title, body, data = {}) {
  for (const userId of userIds) {
    await sendPushNotification(userId, title, body, data);
  }
}
