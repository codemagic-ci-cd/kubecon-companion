{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings on purpose: Flutter's generated
// flutter_service_worker.js only unregisters itself. Offline support comes
// from our own sw.js, registered in index.html.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    const splash = document.getElementById('splash');
    if (splash) splash.remove();
    await appRunner.runApp();
  },
});
