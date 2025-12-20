import { invoke } from '@tauri-apps/api/core'

export type MdnsService = {
  name: string
  host: string
  port: number
  addresses: string[]
}

export type RegistryServer = {
  server_id: string
  device_name: string
  lan_addresses: string[]
  wan_direct_endpoint?: string | null
  overlay_endpoint?: string | null
}

export type AuthTokens = {
  access_token: string
  access_expires_at: string
  token_type: string
}

type FetchOptions = {
  method?: 'GET' | 'POST'
  body?: unknown
  token?: string
  timeoutMs?: number
}

const DEFAULT_TIMEOUT = 6000

function withTimeout(timeoutMs: number) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  return { controller, timer }
}

export function normalizeEndpoint(endpoint: string): string {
  const trimmed = endpoint.trim()
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed.replace(/\/+$/, '')
  }
  return `http://${trimmed.replace(/\/+$/, '')}`
}

export async function fetchJson<T>(
  baseUrl: string,
  path: string,
  options: FetchOptions = {},
): Promise<T> {
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT
  const { controller, timer } = withTimeout(timeoutMs)
  const url = new URL(path, normalizeEndpoint(baseUrl)).toString()
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (options.token) {
    headers.Authorization = `Bearer ${options.token}`
  }
  const res = await fetch(url, {
    method: options.method ?? 'GET',
    body: options.body ? JSON.stringify(options.body) : undefined,
    headers,
    signal: controller.signal,
  })
  clearTimeout(timer)
  if (!res.ok) {
    const text = await res.text().catch(() => '')
    throw new Error(text || `${res.status} ${res.statusText}`)
  }
  return (await res.json()) as T
}

export async function probeEndpoint(baseUrl: string, timeoutMs = 1500): Promise<boolean> {
  try {
    await fetchJson(normalizeEndpoint(baseUrl), '/health', { timeoutMs })
    return true
  } catch {
    return false
  }
}

export async function login(baseUrl: string, email: string, password: string) {
  return fetchJson<AuthTokens>(baseUrl, '/api/v1/auth/login', {
    method: 'POST',
    body: { email, password },
  })
}

export async function signup(baseUrl: string, email: string, password: string) {
  return fetchJson<AuthTokens>(baseUrl, '/api/v1/auth/signup', {
    method: 'POST',
    body: { email, password },
  })
}

export async function startPasswordReset(baseUrl: string, email: string) {
  return fetchJson<{ token: string; expires_at: string }>(
    baseUrl,
    '/api/v1/auth/reset/start',
    {
      method: 'POST',
      body: { email },
    },
  )
}

export async function completePasswordReset(baseUrl: string, token: string, newPassword: string) {
  return fetchJson<string>(baseUrl, '/api/v1/auth/reset/complete', {
    method: 'POST',
    body: { token, new_password: newPassword },
  })
}

export async function fetchRegistryServers(baseUrl: string, token: string) {
  return fetchJson<RegistryServer[]>(baseUrl, '/api/v1/me/servers', { token })
}

export async function discoverMdns(timeoutMs = 1200): Promise<MdnsService[]> {
  try {
    const result = await invoke<MdnsService[]>('discover_mdns', { timeoutMs })
    return Array.isArray(result) ? result : []
  } catch {
    // Ignore when running outside Tauri (e.g., plain Vite dev)
    return []
  }
}

export type ResolvedEndpoint = {
  baseUrl: string
  via: 'lan' | 'wan'
  raw: string
}

export type LibraryItem = {
  id: string
  title: string
  type: string
  year?: number | null
  updated_at: string
  runtime_seconds?: number | null
}

export type LibraryFile = {
  id: string
  path: string
  container?: string | null
  video_codec?: string | null
  audio_codec?: string | null
  size_bytes?: number | null
  scan_state: string
  source_config_id?: string | null
  extension_metadata?: Record<string, unknown> | null
}

export type LibraryDetail = {
  id: string
  title: string
  type: string
  year?: number | null
  runtime_seconds?: number | null
  external_ids: Record<string, unknown>
  metadata?: Record<string, unknown>
  description?: string | null
  genres: string[]
  files: LibraryFile[]
}

export type PlayResponse = {
  session_id: string
  mode: 'direct_play' | 'transcode'
  stream_url: string
  duration_seconds?: number | null
  logical_start_seconds: number
  media_file_id: string
  server_id: string
  wan_direct_endpoint?: string | null
  state: string
  logical_position_seconds: number
}

export type SessionPoll = {
  id: string
  state: string
  mode: string
  logical_position_seconds: number
  duration_seconds?: number | null
  log_path?: string | null
  error?: string | null
}

export async function resolveRegistryEndpoint(
  server: RegistryServer,
): Promise<ResolvedEndpoint | null> {
  const lanCandidates = (server.lan_addresses || []).map((addr) => ({
    raw: addr,
    baseUrl: normalizeEndpoint(addr),
    via: 'lan' as const,
  }))
  const wan = server.wan_direct_endpoint
    ? [
        {
          raw: server.wan_direct_endpoint,
          baseUrl: normalizeEndpoint(server.wan_direct_endpoint),
          via: 'wan' as const,
        },
      ]
    : []
  const candidates = [...lanCandidates, ...wan]
  for (const candidate of candidates) {
    if (await probeEndpoint(candidate.baseUrl)) {
      return candidate
    }
  }
  return null
}

export async function fetchLibraryItems(baseUrl: string, token: string) {
  return fetchJson<LibraryItem[]>(baseUrl, '/api/v1/library/items', { token })
}

export async function fetchLibraryDetail(baseUrl: string, token: string, id: string) {
  return fetchJson<LibraryDetail>(baseUrl, `/api/v1/library/items/${id}`, { token })
}

export async function runScan(baseUrl: string, token: string, forceMetadata = false) {
  return fetchJson<string>(baseUrl, `/api/v1/library/scan?force_metadata=${forceMetadata}`, {
    method: 'POST',
    token,
  })
}

export async function startPlayback(
  baseUrl: string,
  token: string,
  mediaItemId: string,
  preferredFileId?: string | null,
  networkType?: 'lan' | 'wan',
  clientCapabilities?: Record<string, unknown>,
) {
  return fetchJson<PlayResponse>(baseUrl, '/api/v1/play', {
    method: 'POST',
    token,
    body: {
      media_item_id: mediaItemId,
      preferred_file_id: preferredFileId ?? null,
      network_type: networkType,
      client_capabilities: clientCapabilities,
    },
  })
}

export function absoluteUrl(baseUrl: string, path: string) {
  const root = normalizeEndpoint(baseUrl)
  if (path.startsWith('http')) return path
  return `${root}${path.startsWith('/') ? '' : '/'}${path}`
}

export async function pollSession(baseUrl: string, token: string, sessionId: string) {
  return fetchJson<SessionPoll>(baseUrl, `/api/v1/sessions/${sessionId}/poll`, {
    token,
  })
}

export async function endSession(baseUrl: string, token: string, sessionId: string) {
  return fetchJson<string>(baseUrl, `/api/v1/sessions/${sessionId}/end`, {
    method: 'POST',
    token,
  })
}

export async function vlcAvailable(): Promise<boolean> {
  try {
    return await invoke<boolean>('vlc_available')
  } catch {
    return false
  }
}

export async function vlcPlay(url: string): Promise<void> {
  await invoke('vlc_play', { url })
}

export async function vlcStop(): Promise<void> {
  try {
    await invoke('vlc_stop')
  } catch {
    // Ignore
  }
}

export async function vlcEmbedAvailable(): Promise<boolean> {
  try {
    return await invoke<boolean>('vlc_embed_available')
  } catch {
    return false
  }
}

export async function vlcEmbedPlay(url: string): Promise<void> {
  await invoke('vlc_embed_play', { url })
}

export async function vlcEmbedStop(): Promise<void> {
  try {
    await invoke('vlc_embed_stop')
  } catch {
    // ignore
  }
}

export async function vlcEmbedPing(): Promise<boolean> {
  try {
    return await invoke<boolean>('vlc_embed_ping')
  } catch {
    return false
  }
}

export type TrackOption = { id: number; name: string }

export type TrackInfo = {
  audio: TrackOption[]
  current_audio: number
  subtitles: TrackOption[]
  current_subtitle: number
}

export async function vlcEmbedTogglePause(): Promise<boolean> {
  return invoke<boolean>('vlc_embed_toggle_pause')
}

export async function vlcEmbedTracks(): Promise<TrackInfo> {
  return invoke<TrackInfo>('vlc_embed_tracks')
}

export async function vlcEmbedSetAudioTrack(trackId: number): Promise<void> {
  await invoke('vlc_embed_set_audio_track', { trackId })
}

export async function vlcEmbedSetSubtitleTrack(trackId: number): Promise<void> {
  await invoke('vlc_embed_set_subtitle_track', { trackId })
}

export async function seekSession(
  baseUrl: string,
  token: string,
  sessionId: string,
  positionSeconds: number,
) {
  return fetchJson<string>(baseUrl, `/api/v1/sessions/${sessionId}/seek`, {
    method: 'POST',
    token,
    body: { position_seconds: positionSeconds },
  })
}
