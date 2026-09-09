import React, { useEffect, useState } from 'react'
import { createRoot } from 'react-dom/client'
import _ from 'lodash'
import './style.css'

function App() {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)

  useEffect(() => {
    fetch('/api/trace?value=Hello%20Supply%20Chain')
      .then((response) => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        return response.json()
      })
      .then(setData)
      .catch((e) => setError(e.message))
  }, [])

  const tracers = _.sortBy(data?.tracers ?? [])

  return (
    <main>
      <h1>Software Supply Chain Trace Lab</h1>
      <p>This UI deliberately bundles lodash into the production JavaScript.</p>
      {error && <pre>{error}</pre>}
      {data && (
        <section>
          <p><strong>Normalised:</strong> {data.normalized}</p>
          <p><strong>SHA-256:</strong> <code>{data.sha256}</code></p>
          <h2>Tracer components</h2>
          <ul>{tracers.map((name) => <li key={name}>{name}</li>)}</ul>
        </section>
      )}
    </main>
  )
}

createRoot(document.getElementById('root')).render(<App />)
