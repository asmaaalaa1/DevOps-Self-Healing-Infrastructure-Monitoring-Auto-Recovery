from flask import Flask, request, render_template
from signup import Signup, Search
from flask_sqlalchemy import SQLAlchemy

app = Flask(__name__)
app.config['SECRET_KEY'] = '123456'  # add secret key CSR
app.config["SQLALCHEMY_DATABASE_URI"] = 'sqlite:///patient.db'
db = SQLAlchemy(app)


class Patient(db.Model):
    __tablename__ = "Patient"
    NID = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String)
    password = db.Column(db.String, nullable=False)
    mail = db.Column(db.String)
    Fname = db.Column(db.String)
    Lname = db.Column(db.String)
    BD = db.Column(db.TEXT)


@app.route('/', methods=["GET"])
def mainpage():
    return render_template('main.html', main='Main Page')


@app.route('/signup', methods=["POST", "GET"])
def signup():
    form = Signup()
    if request.method == 'GET':
        return render_template('signup.html', form=form)
    elif request.method == 'POST' and form.validate_on_submit():
        NID = form.NID.data
        patient = Patient.query.filter_by(NID=form.NID.data).first()
        password = form.password.data
        if (patient is None) and (password == form.Re_password.data):
            username = form.username.data
            email = form.email.data
            Fname = form.Fname.data
            Lname = form.Lname.data
            BD = form.BD.data
            patient = Patient(
                NID=NID,
                username=username,
                password=password,
                mail=email,
                Fname=Fname,
                Lname=Lname,
                BD=BD
            )
            db.session.add(patient)
            db.session.commit()
            value = (f'user is {username} <br> UID is {NID} <br> '
                     f'mail is {email} <br> Fname is {Fname} <br> '
                     f'Lname is {Lname} <br> Birthday is {BD}')
            return render_template(
                'out.html',
                output=value,
                Statues="This User is added"
            )
        else:
            return render_template(
                'signup.html',
                form=form,
                value="This id is aready IN"
            )


@app.route('/search', methods=["POST", "GET"])
def search():
    form = Search()
    if request.method == 'GET':
        return render_template('search.html', form=form)
    elif request.method == 'POST':
        patient = Patient.query.filter_by(NID=form.NID.data).first()
        if patient is None:
            return render_template('out.html', output="Cant Find a User")
        value = (f'User is {patient.username} <br> UID is {patient.NID} <br> '
                 f'Mail is {patient.mail}')
        return render_template('out.html', output=value)


if __name__ == "__main__":
    with app.app_context():
        db.create_all()
    app.run(host='0.0.0.0', port=8000, debug=True)
