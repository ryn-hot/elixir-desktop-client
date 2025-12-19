import { useEffect, useMemo, useRef, useState } from 'react'
import './App.css'
import type {
  AuthTokens,
  LibraryDetail,
  LibraryItem,
  MdnsService,
  RegistryServer,
  ResolvedEndpoint,
} from './api'
import {
  completePasswordReset,
  fetchLibraryDetail,
  fetchLibraryItems,
  pollSession,
  endSession,
  discoverMdns,
  fetchRegistryServers,
  login,
  normalizeEndpoint,
  probeEndpoint,
  resolveRegistryEndpoint,
  startPlayback,
  signup,
  startPasswordReset,
  absoluteUrl,
  vlcAvailable,
  vlcPlay,
  vlcStop,
  vlcEmbedAvailable,
  vlcEmbedPlay,
  vlcEmbedStop,
  vlcEmbedPing,
  seekSession,
  runScan,
} from './api'
import Hls from 'hls.js'

type ServerOption = {
  key: string
  label: string
  baseUrl: string
  source: 'mdns' | 'registry' | 'manual'
  detail?: string
  via?: 'lan' | 'wan'
}

type SavedSession = {
  baseUrl: string
  label: string
  token?: string
  email?: string
  networkType?: 'lan' | 'wan'
}

type SavedState = {
  lastServer?: string
  servers: Record<string, SavedSession>
}

const STORAGE_KEY = 'elixir-client/session'

function isValidBase(url: string) {
  return (
    (url.startsWith('http://') || url.startsWith('https://')) &&
    url.length > 'http://'.length + 1
  )
}

function formatOrigin(value: string) {
  try {
    return new URL(value).origin
  } catch {
    return value
  }
}

function loadSaved(): SavedState {
  const savedRaw = localStorage.getItem(STORAGE_KEY)
  if (!savedRaw) return { servers: {} }
  try {
    const parsed = JSON.parse(savedRaw) as SavedState
    const filtered: Record<string, SavedSession> = {}
    Object.values(parsed.servers || {}).forEach((s) => {
      if (s.baseUrl && isValidBase(s.baseUrl)) {
        filtered[s.baseUrl] = s
      }
    })
    const last = parsed.lastServer
    const lastValid = last && isValidBase(last) ? last : undefined
    return { servers: filtered, lastServer: lastValid }
  } catch {
    return { servers: {} }
  }
}

function saveState(state: SavedState) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
}

function formatDuration(seconds?: number | null) {
  if (!seconds || seconds <= 0) return '—'
  const mins = Math.floor(seconds / 60)
  const secs = Math.floor(seconds % 60)
  return `${mins}:${secs.toString().padStart(2, '0')}`
}

function withToken(url: string, token: string) {
  if (!token) return url
  const [base, hash] = url.split('#')
  const sep = base.includes('?') ? '&' : '?'
  const next = `${base}${sep}token=${encodeURIComponent(token)}`
  return hash ? `${next}#${hash}` : next
}

export default function App() {
  const [mdnsServers, setMdnsServers] = useState<MdnsService[]>([])
  const [registryServers, setRegistryServers] = useState<RegistryServer[]>([])
  const [registryResolved, setRegistryResolved] = useState<
    Record<string, ResolvedEndpoint | null>
  >({})
  const [selectedServer, setSelectedServer] = useState<ServerOption | null>(null)
  const [manualBase, setManualBase] = useState('http://127.0.0.1:44301')
  const [token, setToken] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [status, setStatus] = useState('Idle')
  const [healthStatus, setHealthStatus] = useState<string>('')
  const [resetEmail, setResetEmail] = useState('')
  const [resetTokenValue, setResetTokenValue] = useState('')
  const [resetPassword, setResetPassword] = useState('')
  const [discoveringMdns, setDiscoveringMdns] = useState(false)
  const [loadingRegistry, setLoadingRegistry] = useState(false)
  const [library, setLibrary] = useState<LibraryItem[]>([])
  const [libraryLoading, setLibraryLoading] = useState(false)
  const [libraryFilter, setLibraryFilter] = useState('')
  const [librarySort, setLibrarySort] = useState<'recent' | 'title' | 'type'>('recent')
  const [selectedItem, setSelectedItem] = useState<LibraryItem | null>(null)
  const [detail, setDetail] = useState<LibraryDetail | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [playbackUrl, setPlaybackUrl] = useState<string | null>(null)
  const [playbackMode, setPlaybackMode] = useState<string | null>(null)
  const [playbackSession, setPlaybackSession] = useState<string | null>(null)
  const [sessionState, setSessionState] = useState<string | null>(null)
  const [sessionError, setSessionError] = useState<string | null>(null)
  const [sessionLogPath, setSessionLogPath] = useState<string | null>(null)
  const [sessionPosition, setSessionPosition] = useState<number | null>(null)
  const [playbackDuration, setPlaybackDuration] = useState<number | null>(null)
  const [pendingSeek, setPendingSeek] = useState<number | null>(null)
  const [bufferedTime, setBufferedTime] = useState<number | null>(null)
  const [debugInfo, setDebugInfo] = useState<string>('')
  const [vlcEnabled, setVlcEnabled] = useState(false)
  const [vlcReady, setVlcReady] = useState(false)
  const [vlcStatus, setVlcStatus] = useState<string>('VLC not checked')
  const [vlcEmbedReady, setVlcEmbedReady] = useState(false)
  const [vlcEmbedEnabled, setVlcEmbedEnabled] = useState(false)
  const [vlcEmbedOverlay, setVlcEmbedOverlay] = useState(false)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const hlsRef = useRef<Hls | null>(null)
  const closeRef = useRef<(() => void) | null>(null)
  const seekTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    const saved = loadSaved()
    if (saved.lastServer) {
      const entry = saved.servers[saved.lastServer]
      if (entry) {
        setManualBase(entry.baseUrl || manualBase)
        setSelectedServer({
          key: entry.baseUrl,
          label: entry.label || 'Saved',
          baseUrl: entry.baseUrl,
          source: 'manual',
          detail: 'Restored',
          via: entry.networkType,
        })
        if (entry.token) {
          setToken(entry.token)
        }
        if (entry.email) {
          setEmail(entry.email)
        }
      }
    }
  }, [])

  useEffect(() => {
    if (!selectedServer) return
    const saved = loadSaved()
    const entry = saved.servers[selectedServer.baseUrl]
    if (entry?.token) {
      setToken(entry.token)
    } else {
      setToken('')
    }
    if (entry?.email) {
      setEmail(entry.email)
    }
  }, [selectedServer?.baseUrl])

  useEffect(() => {
    let cancelled = false
    const run = async () => {
      setDiscoveringMdns(true)
      try {
        const services = await discoverMdns()
        if (!cancelled) {
          setMdnsServers(services)
        }
      } finally {
        if (!cancelled) {
          setDiscoveringMdns(false)
        }
      }
    }
    run()
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    let cancelled = false
    const check = async () => {
      const ok = await vlcAvailable()
      const embedOk = await vlcEmbedAvailable()
      if (!cancelled) {
        setVlcReady(ok)
        setVlcStatus(ok ? 'VLC available' : 'VLC not found on PATH')
        setVlcEmbedReady(embedOk)
      }
    }
    check()
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    // If embed is turned off while playing, stop embedded playback to avoid overlapping surfaces.
    if (!vlcEmbedEnabled) {
      vlcEmbedStop().catch(() => {})
    }
  }, [vlcEmbedEnabled])

  useEffect(() => {
    if (!vlcEmbedEnabled || !vlcEmbedReady) return
    let cancelled = false
    const ping = async () => {
      const ok = await vlcEmbedPing()
      if (!cancelled && !ok) {
        setVlcStatus('libVLC embed not ready')
      }
    }
    ping()
    return () => {
      cancelled = true
    }
  }, [vlcEmbedEnabled, vlcEmbedReady])

  useEffect(() => {
    const handler = async () => {
      if (playbackSession && selectedServer && token) {
        try {
          await endSession(selectedServer.baseUrl, token, playbackSession)
        } catch {
          // ignore
        }
      }
    }
    closeRef.current = handler
    const listener = () => handler()
    window.addEventListener('beforeunload', listener)
    return () => {
      window.removeEventListener('beforeunload', listener)
    }
  }, [playbackSession, selectedServer, token])

  useEffect(() => {
    if (!token || !selectedServer) {
      setRegistryServers([])
      setLibrary([])
      setDetail(null)
      return
    }
    let cancelled = false
    const loadRegistry = async () => {
      setLoadingRegistry(true)
      try {
        const servers = await fetchRegistryServers(selectedServer.baseUrl, token)
        if (!cancelled) {
          setRegistryServers(servers)
          setStatus(`Registry: ${servers.length} server(s)`)
        }
      } catch (err) {
        if (!cancelled) {
          setStatus(`Registry fetch failed: ${String(err)}`)
          setRegistryServers([])
        }
      } finally {
        if (!cancelled) {
          setLoadingRegistry(false)
        }
      }
    }
    loadRegistry()
    return () => {
      cancelled = true
    }
  }, [token, selectedServer?.baseUrl])

  useEffect(() => {
    if (!selectedServer) return
    let cancelled = false
    const check = async () => {
      setHealthStatus('Checking...')
      const ok = await probeEndpoint(selectedServer.baseUrl, 2500)
      if (!cancelled) {
        setHealthStatus(ok ? 'Reachable' : 'No response')
      }
    }
    check()
    return () => {
      cancelled = true
    }
  }, [selectedServer])

  useEffect(() => {
    if (!registryServers.length) {
      setRegistryResolved({})
      return
    }
    let cancelled = false
    const resolveAll = async () => {
      const results: Record<string, ResolvedEndpoint | null> = {}
      for (const srv of registryServers) {
        const resolved = await resolveRegistryEndpoint(srv)
        if (cancelled) return
        results[srv.server_id] = resolved
      }
      if (!cancelled) {
        setRegistryResolved(results)
      }
    }
    resolveAll()
    return () => {
      cancelled = true
    }
  }, [registryServers])

  useEffect(() => {
    if (!selectedServer || !token) {
      setLibrary([])
      setDetail(null)
      return
    }
    let cancelled = false
    const load = async () => {
      setLibraryLoading(true)
      try {
        const items = await fetchLibraryItems(selectedServer.baseUrl, token)
        if (cancelled) return
        setLibrary(items)
        if (items.length && !selectedItem) {
          setSelectedItem(items[0])
        }
      } catch (err) {
        if (!cancelled) {
          setStatus(`Library fetch failed: ${String(err)}`)
          setLibrary([])
        }
      } finally {
        if (!cancelled) {
          setLibraryLoading(false)
        }
      }
    }
    load()
    return () => {
      cancelled = true
    }
  }, [selectedServer?.baseUrl, token])

  useEffect(() => {
    if (!selectedServer || !token || !selectedItem) {
      setDetail(null)
      return
    }
    let cancelled = false
    const loadDetail = async () => {
      setDetailLoading(true)
      try {
        const detailResp = await fetchLibraryDetail(
          selectedServer.baseUrl,
          token,
          selectedItem.id,
        )
        if (!cancelled) {
          setDetail(detailResp)
        }
      } catch (err) {
        if (!cancelled) {
          setStatus(`Detail fetch failed: ${String(err)}`)
          setDetail(null)
        }
      } finally {
        if (!cancelled) {
          setDetailLoading(false)
        }
      }
    }
    loadDetail()
    return () => {
      cancelled = true
    }
  }, [selectedItem?.id, selectedServer?.baseUrl, token])

  useEffect(() => {
    if (pollRef.current) {
      clearInterval(pollRef.current)
      pollRef.current = null
    }
    if (!playbackSession || !selectedServer || !token) {
      return
    }
    const doPoll = async () => {
      try {
        const resp = await pollSession(selectedServer.baseUrl, token, playbackSession)
        setSessionState(resp.state)
        setSessionPosition(resp.logical_position_seconds)
        setSessionLogPath(resp.log_path || null)
        setSessionError(resp.error || null)
      } catch (err) {
        setStatus(`Session poll failed: ${String(err)}`)
      }
    }
    doPoll()
    pollRef.current = setInterval(doPoll, 5000)
    return () => {
      if (pollRef.current) clearInterval(pollRef.current)
    }
  }, [playbackSession, selectedServer?.baseUrl, token])

  useEffect(() => {
    // Clean up HLS when URL changes or when using VLC
    if (hlsRef.current) {
      hlsRef.current.destroy()
      hlsRef.current = null
    }
    if (!playbackUrl || vlcEnabled || vlcEmbedEnabled) {
      if (videoRef.current) {
        videoRef.current.removeAttribute('src')
        videoRef.current.load()
      }
      return
    }
    const video = videoRef.current
    if (!video) return
    if (video.canPlayType('application/vnd.apple.mpegurl')) {
      video.src = playbackUrl
      video.play().catch(() => {})
      return
    }
    if (Hls.isSupported()) {
      const hls = new Hls({ enableWorker: true })
      hls.loadSource(playbackUrl)
      hls.attachMedia(video)
      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        video.play().catch(() => {})
      })
      hls.on(Hls.Events.LEVEL_LOADED, (_event, data) => {
        if (data.details && typeof data.details.totalduration === 'number') {
          setBufferedTime(data.details.totalduration)
        }
      })
      hlsRef.current = hls
    } else {
      setStatus('HLS not supported in this environment.')
    }
    return () => {
      if (hlsRef.current) {
        hlsRef.current.destroy()
        hlsRef.current = null
      }
    }
  }, [playbackUrl, vlcEnabled])

  useEffect(() => {
    const key = normalizeEndpoint(selectedServer?.baseUrl ?? manualBase)
    if (!isValidBase(key)) return
    const stored = loadSaved()
    stored.servers[key] = {
      baseUrl: key,
      label: selectedServer?.label ?? 'Manual',
      token: token || undefined,
      email: email || undefined,
      networkType: selectedServer?.via,
    }
    stored.lastServer = key
    saveState(stored)
  }, [selectedServer, manualBase, token, email])

  useEffect(() => {
    if (selectedServer?.source === 'manual') {
      const normalized = normalizeEndpoint(manualBase)
      if (selectedServer.baseUrl !== normalized) {
        setSelectedServer({
          ...selectedServer,
          baseUrl: normalized,
        })
      }
    }
  }, [manualBase])

  const serverOptions = useMemo<ServerOption[]>(() => {
    const options: ServerOption[] = []
    mdnsServers.forEach((svc, idx) => {
      const addr = svc.addresses[0] || svc.host
      if (!addr) return
      const base = normalizeEndpoint(`${addr}:${svc.port}`)
      options.push({
        key: `mdns-${idx}`,
        label: svc.name || 'LAN server',
        baseUrl: base,
        source: 'mdns',
        detail: 'LAN via mDNS',
        via: 'lan',
      })
    })

    registryServers.forEach((srv) => {
      const resolved = registryResolved[srv.server_id]
      if (!resolved) return
      options.push({
        key: `registry-${srv.server_id}`,
        label: srv.device_name,
        baseUrl: resolved.baseUrl,
        source: 'registry',
        detail: `${resolved.via.toUpperCase()} ${resolved.raw}`,
        via: resolved.via,
      })
    })

    options.push({
      key: 'manual',
      label: 'Manual',
      baseUrl: normalizeEndpoint(manualBase),
      source: 'manual',
      detail: 'Custom endpoint',
    })

    const seen: Record<string, ServerOption> = {}
    for (const opt of options) {
      if (!seen[opt.baseUrl]) {
        seen[opt.baseUrl] = opt
      }
    }
    return Object.values(seen)
  }, [mdnsServers, registryServers, registryResolved, manualBase])

  const filteredLibrary = useMemo(() => {
    const term = libraryFilter.trim().toLowerCase()
    let items = library
    if (term) {
      items = items.filter((i) => i.title.toLowerCase().includes(term))
    }
    items = [...items]
    items.sort((a, b) => {
      if (librarySort === 'title') {
        return a.title.localeCompare(b.title)
      }
      if (librarySort === 'type') {
        return (a.type || '').localeCompare(b.type || '')
      }
      return (b.updated_at || '').localeCompare(a.updated_at || '')
    })
    return items
  }, [library, libraryFilter, librarySort])

  const forceRefreshLibrary = async () => {
    if (!selectedServer || !token) {
      setStatus('Select server and login first')
      return
    }
    setLibraryLoading(true)
    try {
      const items = await fetchLibraryItems(selectedServer.baseUrl, token)
      setLibrary(items)
      setStatus(`Loaded ${items.length} item(s)`)
      setDebugInfo(`Base: ${selectedServer.baseUrl} Token: ${token.slice(0, 8)}...`)
    } catch (err) {
      const msg = `Library fetch failed: ${String(err)}`
      setStatus(msg)
      setDebugInfo(msg)
    } finally {
      setLibraryLoading(false)
    }
  }

  useEffect(() => {
    if (!selectedServer && serverOptions.length > 0) {
      setSelectedServer(serverOptions[0])
    }
  }, [serverOptions, selectedServer])

  const applyTokens = (resp: AuthTokens, context: string) => {
    setToken(resp.access_token)
    setStatus(`${context} successful. Token expires at ${resp.access_expires_at}`)
  }

  const handlePlay = async (preferredFileId?: string | null) => {
    if (!selectedServer || !token || !selectedItem) {
      setStatus('Select server, login, and choose an item first.')
      return
    }
    setStatus('Starting playback...')
    try {
      const resp = await startPlayback(
        selectedServer.baseUrl,
        token,
        selectedItem.id,
        preferredFileId,
        selectedServer.via,
      )
      const absUrl = absoluteUrl(selectedServer.baseUrl, resp.stream_url)
      const authedUrl = withToken(absUrl, token)
      setPlaybackUrl(authedUrl)
      setPlaybackMode(resp.mode)
      setPlaybackSession(resp.session_id)
      setSessionState(resp.state)
      setSessionPosition(resp.logical_position_seconds)
      setPlaybackDuration(resp.duration_seconds ?? detail?.runtime_seconds ?? null)
      if (vlcEmbedEnabled && vlcEmbedReady) {
        setVlcStatus('Embedding libVLC...')
        await vlcEmbedPlay(authedUrl)
        setVlcStatus('libVLC embedded')
      } else if (vlcEnabled && vlcReady) {
        setVlcStatus('Launching VLC...')
        await vlcPlay(authedUrl)
        setVlcStatus('VLC playing')
      }
      setStatus(`Playback ready (${resp.mode}). Session ${resp.session_id}`)
    } catch (err) {
      setStatus(`Playback failed: ${String(err)}`)
    }
  }

  const handleEndSession = async () => {
    if (!selectedServer || !token || !playbackSession) return
    try {
      await endSession(selectedServer.baseUrl, token, playbackSession)
      setStatus('Session ended')
    } catch (err) {
      setStatus(`End failed: ${String(err)}`)
    } finally {
      if (pollRef.current) clearInterval(pollRef.current)
      setPlaybackSession(null)
      setPlaybackUrl(null)
      setSessionState(null)
      setSessionPosition(null)
      setPlaybackMode(null)
      setPlaybackDuration(null)
      if (vlcEmbedEnabled) {
        await vlcEmbedStop()
        setVlcStatus('libVLC stopped')
      } else if (vlcEnabled) {
        await vlcStop()
        setVlcStatus('VLC stopped')
      }
    }
  }

  const handleSeek = (position: number) => {
    setPendingSeek(position)
    if (seekTimer.current) {
      clearTimeout(seekTimer.current)
    }
    seekTimer.current = setTimeout(async () => {
      if (!playbackSession || !selectedServer || !token) {
        if (videoRef.current) {
          videoRef.current.currentTime = position
        }
        setPendingSeek(null)
        return
      }
      setStatus(`Seeking to ${position.toFixed(1)}s...`)
      try {
        await seekSession(selectedServer.baseUrl, token, playbackSession, position)
        setSessionPosition(position)
        const cacheBust = `ts=${Date.now()}`
        if (playbackUrl) {
          const url = playbackUrl.includes('?')
            ? `${playbackUrl}&${cacheBust}`
            : `${playbackUrl}?${cacheBust}`
          setPlaybackUrl(url)
          if (vlcEmbedEnabled && vlcEmbedReady) {
            await vlcEmbedPlay(url)
            setVlcStatus('libVLC playing (after seek)')
          } else if (vlcEnabled && vlcReady) {
            await vlcPlay(url)
            setVlcStatus('VLC playing (after seek)')
          }
        }
        setStatus('Seek complete')
      } catch (err) {
        setStatus(`Seek failed: ${String(err)}`)
      } finally {
        setPendingSeek(null)
      }
    }, 250)
  }

  const ensureServerSelected = () => {
    if (!selectedServer) {
      setStatus('Select a server first')
      return false
    }
    return true
  }

  const handleLogin = async () => {
    if (!ensureServerSelected()) return
    setStatus('Signing in...')
    try {
      const resp = await login(selectedServer!.baseUrl, email, password)
      applyTokens(resp, 'Login')
    } catch (err) {
      setStatus(`Login failed: ${String(err)}`)
    }
  }

  const handleSignup = async () => {
    if (!ensureServerSelected()) return
    setStatus('Creating account...')
    try {
      const resp = await signup(selectedServer!.baseUrl, email, password)
      applyTokens(resp, 'Signup')
    } catch (err) {
      setStatus(`Signup failed: ${String(err)}`)
    }
  }

  const handleResetStart = async () => {
    if (!ensureServerSelected()) return
    setStatus('Requesting reset token...')
    try {
      const res = await startPasswordReset(selectedServer!.baseUrl, resetEmail)
      setResetTokenValue(res.token)
      setStatus(`Reset token issued (expires ${res.expires_at})`)
    } catch (err) {
      setStatus(`Password reset request failed: ${String(err)}`)
    }
  }

  const handleResetComplete = async () => {
    if (!ensureServerSelected()) return
    setStatus('Completing reset...')
    try {
      await completePasswordReset(selectedServer!.baseUrl, resetTokenValue, resetPassword)
      setStatus('Password updated. Sign in with the new password.')
    } catch (err) {
      setStatus(`Reset failed: ${String(err)}`)
    }
  }

  const activeServerLabel = selectedServer
    ? `${selectedServer.label} · ${formatOrigin(selectedServer.baseUrl)}`
    : 'None'

  return (
    <div className="app">
      <header>
        <div>
          <p className="eyebrow">Elixir Client</p>
          <h1>Connect & Auth</h1>
          <p className="lede">
            LAN/WAN aware server selection, login/signup/reset flows wired to the live API.
          </p>
        </div>
        <div className="pill">V1</div>
      </header>

      <section className="panel">
          <div className="panel-head">
            <h2>Servers</h2>
            <p>
              mDNS + registry endpoints are probed automatically (LAN preferred). Select one to
              authenticate.
            </p>
          </div>
          <div className="grid two">
            <div className="box">
              <h3>Available</h3>
              <div className="actions">
                <button
                  className="ghost small"
                  onClick={() => {
                    localStorage.clear()
                    setSelectedServer(null)
                    setToken('')
                    setEmail('')
                    setStatus('Cleared saved servers; reselect manual and login.')
                  }}
                >
                  Reset saved servers
                </button>
                <button className="ghost small" onClick={forceRefreshLibrary} disabled={!token || !selectedServer}>
                  Debug: Refresh via API
                </button>
              </div>
              <ul className="list">
                {serverOptions.map((opt) => (
                  <li key={opt.key} className={selectedServer?.baseUrl === opt.baseUrl ? 'active' : ''}>
                    <div className="row">
                      <span>{opt.label}</span>
                    <small>
                      {formatOrigin(opt.baseUrl)} · {opt.detail || opt.source} · {opt.via || 'auto'}
                    </small>
                  </div>
                  <button className="ghost" onClick={() => setSelectedServer(opt)}>
                    {selectedServer?.baseUrl === opt.baseUrl ? 'Selected' : 'Select'}
                  </button>
                </li>
              ))}
            </ul>
            <div className="hint">
              mDNS {discoveringMdns ? 'scanning…' : 'ready'} · Registry{' '}
              {loadingRegistry ? 'loading…' : `${registryServers.length} item(s)`}
            </div>
          </div>
          <div className="box">
            <h3>Manual endpoint</h3>
            <div className="stack">
              <label>
                Base URL
                <input
                  type="text"
                  value={manualBase}
                  onChange={(e) => setManualBase(e.target.value)}
                  placeholder="http://192.168.1.50:44301"
                />
              </label>
              <button
                className="ghost"
                onClick={() => {
                  const manualOpt =
                    serverOptions.find((o) => o.key === 'manual') || {
                      key: 'manual',
                      label: 'Manual',
                      baseUrl: normalizeEndpoint(manualBase),
                      source: 'manual' as const,
                    }
                  setSelectedServer(manualOpt)
                }}
              >
                Use manual (below list)
              </button>
              <div className="hint">Active: {activeServerLabel}</div>
              <div className="hint">Health: {healthStatus || 'Unknown'}</div>
            </div>
          </div>
        </div>
      </section>

      <section className="panel">
        <div className="panel-head">
          <h2>Login / Signup</h2>
          <p>Bearer tokens are persisted locally for the selected server.</p>
        </div>
        <div className="grid two">
          <div className="box">
            <h3>Credentials</h3>
            <div className="stack">
              <label>
                Email
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                />
              </label>
              <label>
                Password
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••"
                />
              </label>
              <div className="actions">
                <button className="primary" onClick={handleLogin}>
                  Sign in
                </button>
                <button onClick={handleSignup}>Create account</button>
              </div>
              <div className="hint">
                Token: {token ? 'present' : 'none'} · Server: {activeServerLabel}
              </div>
            </div>
          </div>
          <div className="box">
            <h3>Password reset</h3>
            <div className="stack">
              <label>
                Account email
                <input
                  type="email"
                  value={resetEmail}
                  onChange={(e) => setResetEmail(e.target.value)}
                  placeholder="you@example.com"
                />
              </label>
              <button className="ghost" onClick={handleResetStart}>
                Request reset token
              </button>
              <label>
                Reset token
                <input
                  type="text"
                  value={resetTokenValue}
                  onChange={(e) => setResetTokenValue(e.target.value)}
                  placeholder="Paste the token"
                />
              </label>
              <label>
                New password
                <input
                  type="password"
                  value={resetPassword}
                  onChange={(e) => setResetPassword(e.target.value)}
                  placeholder="••••••••"
                />
              </label>
              <button onClick={handleResetComplete}>Complete reset</button>
            </div>
          </div>
        </div>
      </section>

      <section className="panel">
          <div className="panel-head">
            <h2>Library</h2>
            <p>Browse items via /api/v1/library and start playback with the current token.</p>
          </div>
          <div className="grid two">
            <div className="box">
              <div className="row space-between">
                <h3>Items</h3>
                <div className="actions">
                  <button className="ghost small" onClick={() => setSelectedItem(null)}>
                    Clear
                  </button>
                  <button
                    className="ghost small"
                    disabled={!token || !selectedServer}
                    onClick={async () => {
                      if (!selectedServer || !token) return
                      setLibraryLoading(true)
                      try {
                        const items = await fetchLibraryItems(selectedServer.baseUrl, token)
                        setLibrary(items)
                        if (items.length) setSelectedItem(items[0])
                      } catch (err) {
                        setStatus(`Library fetch failed: ${String(err)}`)
                      } finally {
                        setLibraryLoading(false)
                      }
                    }}
                  >
                    Refresh
                  </button>
                  <button
                    className="ghost small"
                    disabled={!token || !selectedServer}
                    onClick={async () => {
                      if (!selectedServer || !token) return
                      setStatus('Scan started...')
                      try {
                        await runScan(selectedServer.baseUrl, token, false)
                        setStatus('Scan requested')
                      } catch (err) {
                        setStatus(`Scan failed: ${String(err)}`)
                      }
                    }}
                  >
                    Scan now
                  </button>
                </div>
              </div>
              <div className="stack">
                <input
                  type="text"
                  placeholder="Filter by title"
                  value={libraryFilter}
                  onChange={(e) => setLibraryFilter(e.target.value)}
                />
                <label>
                  Sort by
                  <select
                    value={librarySort}
                    onChange={(e) => setLibrarySort(e.target.value as any)}
                  >
                    <option value="recent">Recently updated</option>
                    <option value="title">Title</option>
                    <option value="type">Type</option>
                  </select>
                </label>
              </div>
              {libraryLoading && <p className="hint">Loading…</p>}
              <ul className="list">
                {filteredLibrary.map((item) => (
                  <li
                    key={item.id}
                    className={selectedItem?.id === item.id ? 'active' : ''}
                    onClick={() => setSelectedItem(item)}
                  >
                    <div className="row">
                      <span>{item.title}</span>
                      <small>
                        {item.type} · {item.year || '—'} · {formatDuration(item.runtime_seconds)}
                      </small>
                    </div>
                  </li>
                ))}
              </ul>
              {!libraryLoading && !filteredLibrary.length && (
                <p className="hint">No items match this filter. Try scanning or clearing filters.</p>
              )}
            </div>
            <div className="box">
              <h3>Details</h3>
              {detailLoading && <p className="hint">Loading details…</p>}
              {!detail && !detailLoading && <p className="hint">Select an item to view details.</p>}
              {detail && (
                <div className="stack">
                  <div className="row">
                    <strong>{detail.title}</strong>
                    <small>
                      {detail.type} · {detail.year || '—'} · {formatDuration(detail.runtime_seconds)}
                    </small>
                    {detail.description && <small>{detail.description}</small>}
                  </div>
                  <div className="row">
                    <span>Genres: {detail.genres.join(', ') || '—'}</span>
                  </div>
                  <div className="row">
                    <strong>Files</strong>
                    <ul className="list">
                      {detail.files.map((file) => (
                        <li key={file.id}>
                          <div className="row">
                            <span>{file.path}</span>
                            <small>
                              {file.container || '—'} · {file.video_codec || '?'} /{' '}
                              {file.audio_codec || '?'} · {file.scan_state}
                            </small>
                            {file.source_config_id && (
                              <small className="badge">Source: {file.source_config_id}</small>
                            )}
                          </div>
                          {file.scan_state === 'missing' && (
                            <div className="hint error">Missing on disk</div>
                          )}
                          <button
                            className="ghost"
                            onClick={() => handlePlay(file.id)}
                            disabled={!token || file.scan_state === 'missing'}
                          >
                            Play this file
                          </button>
                        </li>
                      ))}
                    </ul>
                    <button className="primary" onClick={() => handlePlay()} disabled={!token}>
                      Play (auto select)
                    </button>
                  </div>
                </div>
              )}
            </div>
          </div>
        </section>

      <section className="panel">
        <div className="panel-head">
          <h2>Player</h2>
          <p>
            Uses the selected endpoint + token; direct/HLS URLs come from /api/v1/play. Toggle VLC
            for native playback.
          </p>
        </div>
        <div className="box player-box">
          <div className="row space-between">
            <label className="inline">
              <input
                type="checkbox"
                checked={vlcEnabled}
                onChange={(e) => {
                  setVlcEnabled(e.target.checked)
                  if (e.target.checked) {
                    setVlcEmbedEnabled(false)
                    setVlcEmbedOverlay(false)
                  }
                }}
                disabled={!vlcReady || vlcEmbedEnabled}
              />{' '}
              Use VLC (native)
            </label>
            <span className="hint">{vlcStatus}</span>
          </div>
          <div className="row space-between">
            <label className="inline">
              <input
                type="checkbox"
                checked={vlcEmbedEnabled}
                onChange={async (e) => {
                  const next = e.target.checked
                  if (next) {
                    const ok = await vlcEmbedPing()
                    if (!ok) {
                      setVlcStatus('libVLC embed not ready; ping failed')
                      setVlcEmbedReady(false)
                      setVlcEmbedEnabled(false)
                      return
                    }
                  }
                  setVlcEmbedEnabled(next)
                  if (next) {
                    setVlcEnabled(false)
                  } else {
                    setVlcEmbedOverlay(false)
                  }
                }}
                disabled={!vlcEmbedReady}
              />{' '}
              Embed libVLC in this window
            </label>
            <span className="hint">{vlcEmbedReady ? 'libVLC embeddable' : 'libVLC not available'}</span>
          </div>
          {vlcEmbedEnabled && (
            <div className="row space-between">
              <label className="inline">
                <input
                  type="checkbox"
                  checked={vlcEmbedOverlay}
                  onChange={(e) => setVlcEmbedOverlay(e.target.checked)}
                />{' '}
                Use overlay mode to keep UI out of the way
              </label>
              <span className="hint">Creates a dark overlay while libVLC renders</span>
            </div>
          )}
          <div className={`video-placeholder ${vlcEmbedEnabled && vlcEmbedOverlay ? 'overlay-active' : ''}`}>
            {vlcEmbedEnabled ? (
              <div className="stack">
                <div className="hint">
                  LibVLC renders directly into the window. UI overlays may be obscured during
                  playback.
                </div>
                {playbackUrl && (
                  <a href={playbackUrl} target="_blank" rel="noreferrer">
                    Stream URL
                  </a>
                )}
              </div>
            ) : vlcEnabled ? (
              <div>
                {playbackUrl ? (
                  <div className="stack">
                    <div className="hint">VLC playing: {playbackMode || 'unknown'} mode</div>
                    <a href={playbackUrl} target="_blank" rel="noreferrer">
                      Open stream URL
                    </a>
                  </div>
                ) : (
                  'Start playback to hand off to VLC'
                )}
              </div>
            ) : (
              <video
                controls
                ref={videoRef}
                style={{ width: '100%', maxHeight: '320px', background: '#000' }}
              >
                {playbackUrl ? 'Loading...' : 'Start playback to preview'}
              </video>
            )}
          </div>
          {playbackUrl && (
            <div className="stack">
              <label>
                Seek
                <input
                  type="range"
                  min={0}
                  max={playbackDuration ?? detail?.runtime_seconds ?? 0}
                  step={1}
                  value={pendingSeek ?? sessionPosition ?? 0}
                  onChange={(e) => handleSeek(Number(e.target.value))}
                />
              </label>
              <div className="hint">
                Position: {sessionPosition?.toFixed(1) ?? '—'}s · Buffered:{' '}
                {bufferedTime ? `${bufferedTime.toFixed(1)}s` : '—'}
              </div>
            </div>
          )}
          {playbackUrl && (
            <div className="stack">
              <div className="time">
                Mode: {playbackMode} · Session: {playbackSession} · State: {sessionState || '—'} ·{' '}
                Position: {sessionPosition?.toFixed(1) ?? '—'}s
              </div>
              {sessionError && (
                <div className="hint error">Session error: {sessionError}</div>
              )}
              {sessionLogPath && (
                <div className="hint">
                  ffmpeg log: <code>{sessionLogPath}</code>
                </div>
              )}
              <div className="actions">
                <a className="ghost" href={playbackUrl} target="_blank" rel="noreferrer">
                  Open stream URL
                </a>
                <button className="ghost" onClick={handleEndSession}>
                  End session
                </button>
              </div>
            </div>
          )}
        </div>
      </section>

      <section className="panel">
        <div className="panel-head">
          <h2>Registry snapshot</h2>
          <p>Auto-select prefers LAN addresses; WAN is used when LAN is unreachable.</p>
        </div>
        <div className="box">
          {registryServers.length === 0 && <p className="hint">No registry entries yet.</p>}
          <ul className="list">
            {registryServers.map((srv) => {
              const resolved = registryResolved[srv.server_id]
              return (
                <li key={srv.server_id}>
                  <div className="row">
                    <span>{srv.device_name}</span>
                    <small>
                      LAN: {srv.lan_addresses?.join(', ') || '—'} · WAN:{' '}
                      {srv.wan_direct_endpoint || '—'}
                    </small>
                    <small>
                      Selected endpoint:{' '}
                      {resolved ? `${resolved.via.toUpperCase()} ${formatOrigin(resolved.baseUrl)}` : 'unreachable'}
                    </small>
                  </div>
                </li>
              )
            })}
          </ul>
        </div>
      </section>

      <section className="panel">
        <div className="panel-head">
          <h2>Status</h2>
          <p>Live feedback for API calls.</p>
        </div>
        <div className="box">
          <div className="status-line">{status}</div>
          {debugInfo && <div className="hint">Debug: {debugInfo}</div>}
        </div>
      </section>
    </div>
  )
}
