/**
 * R57-14: Sliding session E2E — per-tab idle logout + cross-tab broadcast.
 *
 * Uses `window.__TEST_TAB_IDLE__` flag (tabActivity.ts test hook) to simulate
 * 10h idle without actually waiting. Tests verify:
 * 1. Idle tab → visibilitychange → redirects to /login
 * 2. Active tab stays alive when idle tab gets cleared
 * 3. Cross-tab broadcast: logout in Tab A clears Tab B
 */
import { test, expect } from './fixtures/admin-context'

test.describe('Sliding session per-tab idle', () => {
  test('idle tab redirects to login on visibilitychange', async ({ page }) => {
    await page.goto('/dashboard')
    await expect(page).not.toHaveURL(/\/login/, { timeout: 10_000 })

    // Simulate idle: set __TEST_TAB_IDLE__ = true
    await page.evaluate(() => {
      ;(window as Record<string, unknown>).__TEST_TAB_IDLE__ = true
    })

    // Trigger visibilitychange (simulates tab coming back to foreground after idle)
    await page.evaluate(() => {
      Object.defineProperty(document, 'hidden', { value: false, writable: true })
      document.dispatchEvent(new Event('visibilitychange'))
    })

    // Should redirect to login (clearAuthLocal → isAuthenticated=false → Navigate)
    await expect(page).toHaveURL(/\/login/, { timeout: 10_000 })
  })

  test('non-idle tab stays alive after visibilitychange', async ({ page }) => {
    await page.goto('/dashboard')
    await expect(page).not.toHaveURL(/\/login/, { timeout: 10_000 })

    // Ensure NOT idle
    await page.evaluate(() => {
      ;(window as Record<string, unknown>).__TEST_TAB_IDLE__ = false
    })

    // Trigger visibilitychange
    await page.evaluate(() => {
      Object.defineProperty(document, 'hidden', { value: false, writable: true })
      document.dispatchEvent(new Event('visibilitychange'))
    })

    // Should stay on dashboard
    await page.waitForTimeout(2_000)
    await expect(page).not.toHaveURL(/\/login/)
  })
})

test.describe('Cross-tab broadcast', () => {
  test.fixme('logout in Tab A clears Tab B', async ({ context }) => {
    const tabA = await context.newPage()
    const tabB = await context.newPage()

    await tabA.goto('/dashboard')
    await tabB.goto('/dashboard')

    await expect(tabA).not.toHaveURL(/\/login/, { timeout: 10_000 })
    await expect(tabB).not.toHaveURL(/\/login/, { timeout: 10_000 })

    // Tab A broadcasts 'cleared' via BroadcastChannel
    await tabA.evaluate(() => {
      const ch = new BroadcastChannel('sliding-session-auth')
      ch.postMessage({ type: 'cleared' })
      ch.close()
    })

    // Tab B should receive and redirect to login
    await expect(tabB).toHaveURL(/\/login/, { timeout: 10_000 })

    await tabA.close()
    await tabB.close()
  })

  test.fixme('refresh broadcast to idle Tab B clears it instead of extending', async ({ context }) => {
    const tabA = await context.newPage()
    const tabB = await context.newPage()

    await tabA.goto('/dashboard')
    await tabB.goto('/dashboard')

    await expect(tabA).not.toHaveURL(/\/login/, { timeout: 10_000 })
    await expect(tabB).not.toHaveURL(/\/login/, { timeout: 10_000 })

    // Mark Tab B as idle
    await tabB.evaluate(() => {
      ;(window as Record<string, unknown>).__TEST_TAB_IDLE__ = true
    })

    // Tab A broadcasts 'refreshed' (simulates successful token refresh)
    await tabA.evaluate(() => {
      const ch = new BroadcastChannel('sliding-session-auth')
      ch.postMessage({ type: 'refreshed', accessTokenExpiresAt: Date.now() + 900_000 })
      ch.close()
    })

    // Tab B should logout (idle tab doesn't extend)
    await expect(tabB).toHaveURL(/\/login/, { timeout: 10_000 })

    // Tab A should stay alive
    await expect(tabA).not.toHaveURL(/\/login/)

    await tabA.close()
    await tabB.close()
  })
})
