const worker = {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/') {
      return Response.redirect(new URL('/viewer/?u=sevimm', url), 302);
    }

    const response = await env.ASSETS.fetch(request);
    if (response.status !== 404) return response;

    if (url.pathname.startsWith('/viewer/')) {
      return env.ASSETS.fetch(new Request(new URL('/viewer/index.html', url), request));
    }

    if (url.pathname.startsWith('/planner/')) {
      return env.ASSETS.fetch(new Request(new URL('/planner/index.html', url), request));
    }

    return response;
  },
};

export default worker;
