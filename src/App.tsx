import './App.css'

const placeholderServers = [
  { name: 'Local Server', endpoint: 'http://127.0.0.1:44301' },
  { name: 'WAN (example)', endpoint: 'https://example.elixir.media' },
]

export default function App() {
  return (
    <div className="app">
      <header>
        <div>
          <p className="eyebrow">Elixir Client</p>
          <h1>Playback & Library Shell</h1>
          <p className="lede">
            Tauri + React scaffold with room for auth, server selection, and a custom libVLC player.
          </p>
        </div>
        <div className="pill">V1</div>
      </header>

      <section className="panel">
        <div className="panel-head">
          <h2>Connect</h2>
          <p>Choose a server (mDNS/WAN), then log in with your Elixir account.</p>
        </div>
        <div className="grid two">
          <div className="box">
            <h3>Servers</h3>
            <ul className="list">
              {placeholderServers.map((s) => (
                <li key={s.endpoint}>
                  <div className="row">
                    <span>{s.name}</span>
                    <small>{s.endpoint}</small>
                  </div>
                  <button className="ghost">Select</button>
                </li>
              ))}
            </ul>
          </div>
          <div className="box">
            <h3>Credentials</h3>
            <div className="stack">
              <label>
                Email
                <input type="email" placeholder="you@example.com" />
              </label>
              <label>
                Password
                <input type="password" placeholder="••••••••" />
              </label>
              <button className="primary">Sign in</button>
            </div>
          </div>
        </div>
      </section>

      <section className="panel">
        <div className="panel-head">
          <h2>Library</h2>
          <p>Placeholder layout for browse/detail. Wire this up to /api/v1/library/items.</p>
        </div>
        <div className="grid two">
          <div className="box">
            <h3>Items</h3>
            <div className="skeleton list" />
          </div>
          <div className="box">
            <h3>Details</h3>
            <div className="skeleton" />
            <div className="skeleton" />
            <div className="skeleton" />
          </div>
        </div>
      </section>

      <section className="panel">
        <div className="panel-head">
          <h2>Player</h2>
          <p>Custom controls/timebar will drive libVLC. HLS & direct URLs come from /api/v1/play.</p>
        </div>
        <div className="box player-box">
          <div className="video-placeholder">Video Surface</div>
          <div className="controls">
            <div className="time">00:00 / 00:00</div>
            <div className="bar">
              <div className="bar-fill" style={{ width: '20%' }} />
            </div>
            <div className="actions">
              <button className="ghost">Play</button>
              <button className="ghost">Pause</button>
              <button className="ghost">Seek +30s</button>
            </div>
          </div>
        </div>
      </section>
    </div>
  )
}
