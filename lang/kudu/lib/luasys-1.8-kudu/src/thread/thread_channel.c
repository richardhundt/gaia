/* Lua Threading: Channnel */

#define CHANNEL_TYPENAME	"sys.thread.channel"

struct channel {
    unsigned int volatile n;  /* count of data in storage */

    int volatile nput; /* number of items to put as new data */

    unsigned int idx, top;  /* storage indexes */
    unsigned int max;  /* maximum watermark of data */

    thread_cond_t put;  /* synchronization */
    thread_cond_t get;  /* synchronization */

    thread_critsect_t mutex;
};


static int
thread_channel (lua_State *L)
{
    struct channel *chan = lua_newuserdata(L, sizeof(struct channel));
    memset(chan, 0, sizeof(struct channel));
    chan->max = (unsigned int) -1;

    if (!thread_cond_new(&chan->put) && !thread_cond_new(&chan->get)) {
        thread_critsect_new(&chan->mutex);
	luaL_getmetatable(L, CHANNEL_TYPENAME);
	lua_setmetatable(L, -2);

	lua_newtable(L);  /* data storage */
	lua_setfenv(L, -2);
	return 1;
    }
    return sys_seterror(L, 0);
}

static int
channel_done (lua_State *L)
{
    struct channel *chan = checkudata(L, 1, CHANNEL_TYPENAME);

    thread_cond_del(&chan->put);
    thread_cond_del(&chan->get);
    thread_critsect_del(&chan->mutex);
    return 0;
}

static int
channel_put (lua_State *L)
{
    struct sys_thread *td = sys_get_thread();
    struct channel *chan = checkudata(L, 1, CHANNEL_TYPENAME);
    int nput = lua_gettop(L) - 1;

    if (!td) luaL_argerror(L, 0, "Threading not initialized");
    if (!nput) luaL_argerror(L, 2, "data expected");

    lua_getfenv(L, 1);  /* get the storage table */
    lua_insert(L, 1);

    sys_vm_leave();

    thread_critsect_enter(&chan->mutex);
    thread_cond_signal(&chan->put);

    /* move the data to storage */
    {
	int top = chan->top;

	lua_pushinteger(L, nput);
	do {
	    lua_rawseti(L, 1, ++top);
	} while (nput--);
	chan->top = top;
        chan->n++;
    }

    while (chan->n > chan->max) {
        thread_cond_wait(&chan->get, &chan->mutex, TIMEOUT_INFINITE);
    }

    thread_critsect_leave(&chan->mutex);

    sys_vm_enter();
    return 0;
}

static int
channel_get (lua_State *L)
{
    struct channel *chan = checkudata(L, 1, CHANNEL_TYPENAME);
    const msec_t timeout = lua_isnoneornil(L, 2)
     ? TIMEOUT_INFINITE : (msec_t) lua_tointeger(L, 2);
    int nput;
    int idx;
    int i;

    lua_settop(L, 1);
    lua_getfenv(L, 1);  /* storage */
    lua_insert(L, 1);

    sys_vm_leave();

    thread_critsect_enter(&chan->mutex);
    thread_cond_signal(&chan->get);

    /* wait signal */
    while (chan->n == 0) {
        thread_cond_wait(&chan->put, &chan->mutex, timeout);
    }

    /* get from storage */
    idx = chan->idx + 1;

    lua_rawgeti(L, 1, idx);
    nput = lua_tointeger(L, -1);
    lua_pushnil(L);
    lua_rawseti(L, 1, idx);
    chan->idx = idx + nput;

    for (i = chan->idx; i > idx; --i) {
        lua_rawgeti(L, 1, i);
        lua_pushnil(L);
        lua_rawseti(L, 1, i);
    }

    if (chan->idx == chan->top) chan->idx = chan->top = 0;
    chan->n--;

    thread_critsect_leave(&chan->mutex);

    sys_vm_enter();

    return nput;
}

static int
channel_max (lua_State *L)
{
    struct channel *chan = checkudata(L, 1, CHANNEL_TYPENAME);

    if (lua_isnoneornil(L, 2))
	lua_pushinteger(L, chan->max);
    else {
	chan->max = luaL_checkinteger(L, 2);
	lua_settop(L, 1);
    }
    return 1;
}

static int
channel_count (lua_State *L)
{
    struct channel *chan = checkudata(L, 1, CHANNEL_TYPENAME);

    lua_pushinteger(L, chan->n);
    return 1;
}

static int
channel_tostring (lua_State *L)
{
    struct channel *chan = checkudata(L, 1, CHANNEL_TYPENAME);
    lua_pushfstring(L, "[chan: %p]", chan);
    return 1;
}

static luaL_reg channel_meth[] = {
    {"put",		channel_put},
    {"get",		channel_get},
    {"max",		channel_max},
    {"__len",		channel_count},
    {"__tostring",	channel_tostring},
    {"__gc",		channel_done},
    {NULL, NULL}
};
