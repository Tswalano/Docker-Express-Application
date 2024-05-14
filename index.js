const express = require('express')

const data = require('./db.json')

const app = express()
const port = 3000

// get all users
app.get('/', (req, res) => {
    res.send({
        data,
        error: null,
        status: 200
    })
})

// get user
app.get('/user/:id', (req, res) => {

    const id = req.params.id
    const user = data.filter(user => user.id == id)

    if (user.length == 0) {
        res.send({
            data: null,
            error: {
                message: "User not found",
                code: "NOT_FOUND"
            },
            status: 404
        })
    }

    res.send({
        data: user,
        error: null,
        status: 200
    })
})

// get random user
app.get('/users/random', (req, res) => {

    const user = data[Math.floor(Math.random() * data.length)]
    res.send({
        data: user,
        error: null,
        status: 200
    })
})

app.listen(port, () => {
    console.log(`Example app listening on port ${port}`)
})