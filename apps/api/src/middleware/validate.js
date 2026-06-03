// Joi schema validation middleware factory
function validate(schema, target = 'body') {
  return (req, res, next) => {
    const { error, value } = schema.validate(req[target], { abortEarly: false, stripUnknown: true })
    if (error) {
      const details = error.details.map((d) => ({ field: d.path.join('.'), message: d.message }))
      return res.status(422).json({ error: 'Datos inválidos', details })
    }
    req[target] = value
    next()
  }
}

module.exports = { validate }
